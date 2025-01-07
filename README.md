# Azure-Reservation-List

This PowerShell script provides a simple way to list both active and expired Azure VM reservations. It handles Azure authentication, retrieves reservation data, and sends email alerts for reservations nearing expiration.

## Features

- Lists active and inactive Azure Reserved VM Instances for a given subscription
- Sends email alerts for expiring reservations
- Supports filtering for active or expired reservations only
- Customizable sender email address for alerts
- Supports running in Azure Automation runbooks using managed identity

## Prerequisites

The script requires the following PowerShell modules:

- Az.Accounts
- Az.Reservations
- Microsoft.Graph.Authentication
- Microsoft.Graph.Mail

These modules will be automatically installed if not present.

## Usage

```powershell
./Azure-Reservation-List.ps1 [[-ActiveOnly] | [-ExpiredOnly]] [-SenderEmail <email_address>] [-UseManagedIdentity]
```

### Parameters

- `-ActiveOnly`: Switch to display only active reservations.
- `-ExpiredOnly`: Switch to display only expired reservations.
- `-SenderEmail`: The email address to use as the sender for alert emails. Defaults to noreply@yourdomain.com if not specified.
- `-UseManagedIdentity`: Switch to use managed identity for authentication when running in an Azure Automation runbook.

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

5. Run using managed identity in an Azure Automation runbook:
   ```powershell
   ./Azure-Reservation-List.ps1 -UseManagedIdentity
   ```

6. Combine multiple parameters:
   ```powershell
   ./Azure-Reservation-List.ps1 -ActiveOnly -UseManagedIdentity -SenderEmail "azure-alerts@mycompany.com"
   ```

## Email Alerts

The script sends email alerts when reservations reach 180, 90, 30, 15, 10, 5, or 1 day(s) remaining.

## License

This project is licensed under the BSD License. See the [LICENSE](LICENSE) file for details.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Author

Edward Crotty

## Acknowledgments

- Microsoft Azure Documentation
- PowerShell Community
