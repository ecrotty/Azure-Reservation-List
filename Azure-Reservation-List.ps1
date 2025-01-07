# Azure-Reservation-List.ps1
#
# Author: Edward Crotty
# GitHub: https://github.com/ecrotty/Azure-Reservation-List
# License: BSD License
#
# .SYNOPSIS
# Lists active and inactive Azure Reserved VM Instances for a given subscription, sends email alerts for expiring reservations, and optionally logs metrics to Azure Log Analytics.
#
# .DESCRIPTION
# This script provides a comprehensive solution for managing Azure VM reservations:
# - Lists both active and expired Azure VM reservations
# - Sends email alerts for reservations nearing expiration (180, 90, 30, 15, 10, 5, or 1 day(s) remaining)
# - Optionally logs metrics to Azure Log Analytics when running with Managed Identity
#
# The script supports both interactive use and execution as an Azure Automation runbook.
#
# .NOTES
# Required Modules: Az.Accounts, Az.Reservations, Microsoft.Graph.Authentication, Microsoft.Graph.Mail
#
# .PARAMETER ActiveOnly
# Switch to display only active reservations.
#
# .PARAMETER ExpiredOnly
# Switch to display only expired reservations.
#
# .PARAMETER SenderEmail
# The email address to use as the sender for alert emails. Defaults to noreply@yourdomain.com if not specified.
#
# .PARAMETER UseManagedIdentity
# Switch to use managed identity for authentication. This should be used when running the script as an Azure Automation runbook.
#
# .PARAMETER LogAnalyticsWorkspaceId
# The Workspace ID of the Log Analytics workspace for logging metrics. Only used when -UseManagedIdentity is specified.
#
# .PARAMETER LogAnalyticsSharedKey
# The Shared Key of the Log Analytics workspace for logging metrics. Only used when -UseManagedIdentity is specified.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1
# Runs the script interactively, listing all reservations and sending email alerts.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1 -ActiveOnly
# Lists only active reservations and sends email alerts.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1 -ExpiredOnly
# Lists only expired reservations and sends email alerts.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1 -SenderEmail "azure-alerts@mycompany.com"
# Uses the specified email address as the sender for alert emails.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1 -UseManagedIdentity -LogAnalyticsWorkspaceId "workspace-id" -LogAnalyticsSharedKey "workspace-key"
# Runs the script using Managed Identity (for Azure Automation) and logs metrics to the specified Log Analytics workspace.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1 -ActiveOnly -UseManagedIdentity -LogAnalyticsWorkspaceId "workspace-id" -LogAnalyticsSharedKey "workspace-key" -SenderEmail "azure-alerts@mycompany.com"
# Combines multiple parameters: lists only active reservations, uses Managed Identity, logs to Log Analytics, and specifies a sender email.

param (
    [switch]$ActiveOnly,
    [switch]$ExpiredOnly,
    [string]$SenderEmail = "noreply@yourdomain.com",
    [switch]$UseManagedIdentity,
    [string]$LogAnalyticsWorkspaceId,
    [string]$LogAnalyticsSharedKey,
    [switch]$Help
)

if ($Help) {
    Write-Host "Azure-Reservation-List.ps1 - Lists Azure Reserved VM Instances"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -ActiveOnly                 Display only active reservations"
    Write-Host "  -ExpiredOnly                Display only expired reservations"
    Write-Host "  -SenderEmail <email>        Specify the sender email for alerts (default: noreply@yourdomain.com)"
    Write-Host "  -UseManagedIdentity         Use managed identity for authentication"
    Write-Host "  -LogAnalyticsWorkspaceId    Specify the Log Analytics Workspace ID"
    Write-Host "  -LogAnalyticsSharedKey      Specify the Log Analytics Shared Key"
    Write-Host "  -Help                       Display this help message"
    exit 0
}

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function to get reservations
function Get-AzureReservations {
    Write-Host "Retrieving Azure reservations..."
    $allReservations = @(Get-AzReservation)
    
    if ($allReservations.Count -eq 0) {
        Write-Host "No reservations found." -ForegroundColor Yellow
        return $null
    }
    
    $currentDate = Get-Date
    $expiredReservations = @($allReservations | Where-Object { $_.ExpiryDate -lt $currentDate })
    $activeReservations = @($allReservations | Where-Object { $_.ExpiryDate -ge $currentDate })
    
    $expiredCount = $expiredReservations.Count
    $activeCount = $activeReservations.Count
    
    Write-Host "Found $activeCount active reservation(s)." -ForegroundColor Green
    Write-Host "Found $expiredCount expired reservation(s)." -ForegroundColor Yellow
    
    return @{
        Active = $activeReservations
        Expired = $expiredReservations
    }
}

# Function to safely get count
function Get-SafeCount($array) {
    if ($null -eq $array) { return 0 }
    if ($array -is [array]) { return $array.Count }
    return 1  # If it's a single object, count as 1
}

# Check if Log Analytics settings are provided when using Managed Identity
if ($UseManagedIdentity -and (-not $LogAnalyticsWorkspaceId -or -not $LogAnalyticsSharedKey)) {
    Write-Warning "Log Analytics Workspace ID and Shared Key are required when using Managed Identity for full functionality. Metrics will not be sent to Log Analytics."
}

# Function to send data to Log Analytics
function Send-LogAnalyticsData {
    param (
        [string]$customerId,
        [string]$sharedKey,
        [object]$body
    )

    if (-not $customerId -or -not $sharedKey) {
        Write-Warning "Log Analytics Workspace ID or Shared Key not provided. Skipping metric submission."
        return
    }

    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource

    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = "AzureReservationMetrics";
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = "";
    }

    try {
        $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
        Write-Host "Data successfully sent to Log Analytics" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to send data to Log Analytics: $_"
    }
}

# Function to install and import required modules
function Initialize-RequiredModules {
    $requiredModules = @(
        'Az.Accounts',
        'Az.Reservations',
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Mail'
    )
    
    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing required module: $module"
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
        }
        
        Write-Host "Importing module: $module"
        Import-Module -Name $module -Force
    }
}

# Function to connect to Microsoft Graph
function Connect-ToMicrosoftGraph {
    try {
        $graphConnection = Get-MgContext
        if (-not $graphConnection) {
            Write-Host "No Microsoft Graph context found. Initiating login..."
            if ($UseManagedIdentity) {
                Connect-MgGraph -Identity
            } else {
                Connect-MgGraph -Scopes "Mail.Send"
            }
            Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
        } else {
            Write-Host "Already connected to Microsoft Graph" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph. Error: $_"
        exit 1
    }
}

# Function to ensure Azure connection
function Connect-ToAzure {
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "No Azure context found. Initiating login..."
            if ($UseManagedIdentity) {
                Connect-AzAccount -Identity
            } else {
                Connect-AzAccount
            }
        } else {
            Write-Host "Already connected to Azure" -ForegroundColor Green
        }
        
        if (-not $UseManagedIdentity) {
            $subscriptions = @(Get-AzSubscription)
            if ($subscriptions.Count -eq 0) {
                throw "No subscriptions found for the current account"
            }
            
            if ($subscriptions.Count -eq 1) {
                Write-Host "Only one subscription available. Using: $($subscriptions[0].Name)"
                $selectedSubscription = $subscriptions[0]
            } else {
                Write-Host "Available subscriptions:"
                for ($i = 0; $i -lt $subscriptions.Count; $i++) {
                    Write-Host "$($i + 1). $($subscriptions[$i].Name)"
                }
                
                $selection = Read-Host "Enter the number of the subscription you want to use"
                $selectedSubscription = $subscriptions[$selection - 1]
                
                if (-not $selectedSubscription) {
                    throw "Invalid selection"
                }
            }
            
            $context = Set-AzContext -Subscription $selectedSubscription.Id
        } else {
            $context = Get-AzContext
        }
        
        Write-Host "Connected to Azure subscription: $($context.Subscription.Name)"
        return $context
    }
    catch {
        Write-Error "Failed to connect to Azure. Error: $_"
        exit 1
    }
}

# Function to display reservations
function Display-Reservations {
    param (
        [array]$reservations,
        [string]$status,
        [string]$senderEmail
    )

    Write-Host "`n$status Reservations:" -ForegroundColor Cyan
    Write-Host "------------------------" -ForegroundColor Cyan

    if ((Get-SafeCount $reservations) -eq 0) {
        Write-Host "No $status reservations found."
    } else {
        foreach ($reservation in $reservations) {
            $daysRemaining = ($reservation.ExpiryDate - (Get-Date)).Days
            
            $warningColor = if ($daysRemaining -le 0) {
                "Red"
            } elseif ($daysRemaining -le 30) {
                switch ($daysRemaining) {
                    {$_ -le 5} { "DarkRed" }
                    {$_ -le 10} { "Yellow" }
                    {$_ -le 15} { "DarkYellow" }
                    default { "Magenta" }
                }
            } else { "White" }

            Write-Host "Reservation ID: $($reservation.Id)"
            Write-Host "SKU: $($reservation.SkuName)"
            Write-Host "Start Date: $($reservation.EffectiveDateTime)"
            Write-Host "Expiry Date: $($reservation.ExpiryDate)"
            Write-Host "Quantity: $($reservation.Quantity)"
            Write-Host "Days Remaining: " -NoNewline
            Write-Host $daysRemaining -ForegroundColor $warningColor
            Write-Host "------------------------"

            if ($daysRemaining -in @(1, 5, 10, 15, 30, 90, 180)) {
                Send-ExpirationNotification -reservationId $reservation.Id -daysRemaining $daysRemaining -senderEmail $senderEmail
            }
        }
    }
}

# Function to send email notifications
function Send-ExpirationNotification {
    param (
        [string]$reservationId,
        [int]$daysRemaining,
        [string]$senderEmail
    )

    Write-Host "Sending notification for reservation $reservationId with $daysRemaining days remaining..."

    $timeFrame = switch ($daysRemaining) {
        180 { "6 months" }
        90 { "3 months" }
        30 { "1 month" }
        15 { "15 days" }
        10 { "10 days" }
        5 { "5 days" }
        1 { "1 day" }
        default { "$daysRemaining days" }
    }

    $params = @{
        Message = @{
            Subject = "Azure Reservation Expiration Notice"
            Body = @{
                ContentType = "Text"
                Content = "Azure Reservation $reservationId will expire in $timeFrame. Please take appropriate action."
            }
            ToRecipients = @(
                @{
                    EmailAddress = @{
                        Address = $senderEmail
                    }
                }
            )
        }
    }

    try {
        if ($UseManagedIdentity) {
            Send-MgUserMail -BodyParameter $params
        } else {
            Send-MgUserMail -UserId $senderEmail -BodyParameter $params
        }
        Write-Host "Email notification sent for reservation $reservationId" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to send email notification for reservation $reservationId. Error: $_" -ForegroundColor Red
    }
}

# Main script execution
try {
    Write-Host "Initializing Azure Reservation Listing..."
    
    # Install and import required modules
    Initialize-RequiredModules
    
    # Connect to Microsoft Graph
    Connect-ToMicrosoftGraph
    
    # Ensure Azure connection
    Connect-ToAzure
    
    # Get reservations
    $reservations = Get-AzureReservations
    
    if ($null -eq $reservations) {
        Write-Host "No reservations found. Exiting script." -ForegroundColor Yellow
        exit 0
    }

    # Initialize counters for Azure Monitor
    $expiringReservationsCount = 0
    $totalActiveReservations = Get-SafeCount $reservations.Active
    $totalExpiredReservations = Get-SafeCount $reservations.Expired

    # Display reservations based on parameters
    if ($ActiveOnly) {
        Display-Reservations -reservations $reservations.Active -status "Active" -senderEmail $SenderEmail
        $expiringReservationsCount = @($reservations.Active | Where-Object { ($_.ExpiryDate - (Get-Date)).Days -in 1..180 }).Count
    } elseif ($ExpiredOnly) {
        Display-Reservations -reservations $reservations.Expired -status "Expired" -senderEmail $SenderEmail
    } else {
        Display-Reservations -reservations $reservations.Active -status "Active" -senderEmail $SenderEmail
        Display-Reservations -reservations $reservations.Expired -status "Expired" -senderEmail $SenderEmail
        $expiringReservationsCount = @($reservations.Active | Where-Object { ($_.ExpiryDate - (Get-Date)).Days -in 1..180 }).Count
    }

    # Send metrics to Log Analytics only if using Managed Identity and LAW settings are provided
    if ($UseManagedIdentity -and $LogAnalyticsWorkspaceId -and $LogAnalyticsSharedKey) {
        $metrics = @{
            "TotalActiveReservations" = $totalActiveReservations
            "TotalExpiredReservations" = $totalExpiredReservations
            "ExpiringReservations" = $expiringReservationsCount
            "ScriptExecutionSuccess" = 1
        }
        Send-LogAnalyticsData -customerId $LogAnalyticsWorkspaceId -sharedKey $LogAnalyticsSharedKey -body ($metrics | ConvertTo-Json)
    }

    Write-Host "Script execution completed successfully." -ForegroundColor Green
} catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    # Send failure metric to Log Analytics only if using Managed Identity and LAW settings are provided
    if ($UseManagedIdentity -and $LogAnalyticsWorkspaceId -and $LogAnalyticsSharedKey) {
        $metrics = @{
            "ScriptExecutionSuccess" = 0
        }
        Send-LogAnalyticsData -customerId $LogAnalyticsWorkspaceId -sharedKey $LogAnalyticsSharedKey -body ($metrics | ConvertTo-Json)
    }
    exit 1
} finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}