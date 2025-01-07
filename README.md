# Azure-Reservation-List

This PowerShell script provides a comprehensive solution for managing Azure VM reservations. It lists both active and expired Azure VM reservations, sends email alerts for reservations nearing expiration, and optionally logs metrics to Azure Log Analytics when running as an Azure Automation runbook.

## Features

- Lists active and inactive Azure Reserved VM Instances for a given subscription
- Sends email alerts for expiring reservations (180, 90, 30, 15, 10, 5, or 1 day(s) remaining)
- Supports filtering for active or expired reservations only
- Customizable sender email address for alerts
- Supports running in Azure Automation runbooks using managed identity
- Optional logging of metrics to Azure Log Analytics when running with Managed Identity

## Prerequisites

The script requires the following PowerShell modules:

- Az.Accounts
- Az.Reservations
- Microsoft.Graph.Authentication
- Microsoft.Graph.Mail

These modules will be automatically installed if not present.

## Usage

```powershell
./Azure-Reservation-List.ps1 [[-ActiveOnly] | [-ExpiredOnly]] [-SenderEmail <email_address>] [-UseManagedIdentity] [-LogAnalyticsWorkspaceId <workspace_id>] [-LogAnalyticsSharedKey <shared_key>] [-Help]
```

### Parameters

- `-ActiveOnly`: Switch to display only active reservations.
- `-ExpiredOnly`: Switch to display only expired reservations.
- `-SenderEmail`: The email address to use as the sender for alert emails. Defaults to noreply@yourdomain.com if not specified.
- `-UseManagedIdentity`: Switch to use managed identity for authentication. This should be used when running the script as an Azure Automation runbook.
- `-LogAnalyticsWorkspaceId`: The Workspace ID of the Log Analytics workspace for logging metrics. Only used when -UseManagedIdentity is specified.
- `-LogAnalyticsSharedKey`: The Shared Key of the Log Analytics workspace for logging metrics. Only used when -UseManagedIdentity is specified.
- `-Help`: Display the help message.

### Examples

1. List all reservations:
   ```powershell
   ./Azure-Reservation-List.ps1
   ```

2. List only active reservations:
   ```powershell
   ./Azure-Reservation-List.ps1 -ActiveOnly
   ```

3. List only expired reservations:
   ```powershell
   ./Azure-Reservation-List.ps1 -ExpiredOnly
   ```

4. Use a custom sender email for alerts:
   ```powershell
   ./Azure-Reservation-List.ps1 -SenderEmail "azure-alerts@mycompany.com"
   ```

5. Run using managed identity in an Azure Automation runbook and log metrics to Log Analytics:
   ```powershell
   ./Azure-Reservation-List.ps1 -UseManagedIdentity -LogAnalyticsWorkspaceId "workspace-id" -LogAnalyticsSharedKey "workspace-key"
   ```

6. Combine multiple parameters:
   ```powershell
   ./Azure-Reservation-List.ps1 -ActiveOnly -UseManagedIdentity -LogAnalyticsWorkspaceId "workspace-id" -LogAnalyticsSharedKey "workspace-key" -SenderEmail "azure-alerts@mycompany.com"
   ```

7. Display help message:
   ```powershell
   ./Azure-Reservation-List.ps1 -Help
   ```

## Email Alerts

The script sends email alerts when reservations reach 180, 90, 30, 15, 10, 5, or 1 day(s) remaining.

## Azure Log Analytics Integration

When running with Managed Identity (-UseManagedIdentity) and provided with Log Analytics Workspace details, the script logs the following metrics:

- TotalActiveReservations
- TotalExpiredReservations
- ExpiringReservations (reservations expiring within 180 days)
- ScriptExecutionSuccess (1 for success, 0 for failure)

This allows for monitoring and alerting on reservation status using Azure Monitor.

## Running as an Azure Automation Runbook

To run this script as an Azure Automation runbook:

1. Import the script into your Azure Automation account.
2. Ensure the required modules are available in your Automation account.
3. Configure a Managed Identity for your Automation account and grant it the necessary permissions:
   - "Reservation Reader" role at the subscription level
   - "Mail.Send" permission in Azure AD
4. Create a runbook that calls this script with the -UseManagedIdentity parameter.
5. If you want to log metrics, provide the Log Analytics Workspace ID and Shared Key as parameters.

## License

This project is licensed under the BSD License. See the [LICENSE](LICENSE) file for details.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Author

Edward Crotty

## Acknowledgments

- Microsoft Azure Documentation
- PowerShell Community
