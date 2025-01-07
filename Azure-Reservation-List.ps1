# Azure-Reservation-List.ps1
#
# Author: Edward Crotty
# GitHub: https://github.com/ecrotty/Azure-Reservation-List
# License: BSD License
#
# .SYNOPSIS
# Lists active and inactive Azure Reserved VM Instances for a given subscription and sends email alerts for expiring reservations.
#
# .DESCRIPTION
# This script provides a simple way to list both active and expired Azure VM reservations.
# It handles Azure authentication, retrieves reservation data, and sends email alerts for reservations nearing expiration.
#
# Email alerts are sent when reservations reach 180, 90, 30, 15, 10, 5, or 1 day(s) remaining.
# The sender email address can be specified using the -SenderEmail parameter. If not provided, it defaults to noreply@yourdomain.com.
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
# Switch to use managed identity for authentication when running in an Azure Automation runbook.
#
# .EXAMPLE
# ./Azure-Reservation-List.ps1
# ./Azure-Reservation-List.ps1 -ActiveOnly
# ./Azure-Reservation-List.ps1 -ExpiredOnly
# ./Azure-Reservation-List.ps1 -SenderEmail "azure-alerts@mycompany.com"
# ./Azure-Reservation-List.ps1 -UseManagedIdentity
# ./Azure-Reservation-List.ps1 -ActiveOnly -UseManagedIdentity -SenderEmail "azure-alerts@mycompany.com"

param (
    [switch]$ActiveOnly,
    [switch]$ExpiredOnly,
    [string]$SenderEmail = "noreply@yourdomain.com",
    [switch]$UseManagedIdentity
)

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# Function to get reservations
function Get-AzureReservations {
    Write-Host "Retrieving Azure reservations..."
    $allReservations = @(Get-AzReservation)
    
    $expiredReservations = @($allReservations | Where-Object { $_.ExpiryDate -lt (Get-Date) })
    $activeReservations = @($allReservations | Where-Object { $_.ExpiryDate -ge (Get-Date) })
    
    $expiredCount = ($expiredReservations | Measure-Object).Count
    $activeCount = ($activeReservations | Measure-Object).Count
    
    Write-Host "Found $activeCount active reservation(s)." -ForegroundColor Green
    Write-Host "Found $expiredCount expired reservation(s)." -ForegroundColor Yellow
    
    return @{
        Active = $activeReservations
        Expired = $expiredReservations
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

    if ($reservations.Count -eq 0) {
        Write-Host "No $status reservations found."
    } else {
        foreach ($reservation in $reservations) {
            $daysRemaining = ($reservation.ExpiryDate - (Get-Date)).Days
            $warningColor = if ($daysRemaining -le 30) {
                switch ($daysRemaining) {
                    {$_ -le 1} { "Red" }
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
    
    # Ensure Azure connection
    Connect-ToAzure
    
    # Connect to Microsoft Graph
    Connect-ToMicrosoftGraph
    
    # Get reservations
    $reservations = Get-AzureReservations
    
    # If SenderEmail is not provided and using managed identity, try to get it from the context
    if ($UseManagedIdentity -and [string]::IsNullOrEmpty($SenderEmail)) {
        $context = Get-AzContext
        $SenderEmail = $context.Account.Id
        Write-Host "Using $SenderEmail as the sender email address"
    }
    
    # Display reservations based on parameters
    if ($ActiveOnly) {
        Display-Reservations -reservations $reservations.Active -status "Active" -senderEmail $SenderEmail
    } elseif ($ExpiredOnly) {
        Display-Reservations -reservations $reservations.Expired -status "Expired" -senderEmail $SenderEmail
    } else {
        Display-Reservations -reservations $reservations.Active -status "Active" -senderEmail $SenderEmail
        Display-Reservations -reservations $reservations.Expired -status "Expired" -senderEmail $SenderEmail
    }
    
} catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
} finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}
