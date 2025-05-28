<#
.SYNOPSIS
Checks Exchange mail queues across mailbox servers in the environment. If a queue length exceeds the set threshold and continues to grow, the script sends an email alert to the team. 
Author: Rafat Sumreen
Date: 05/05/2025
#>

#Config
$KeyPath = "D:\ExchangeScripts\Creds\key.bin"
$SecurePasswordPath = "D:\ExchangeScripts\Creds\secure-password.txt" 
$UserName = "Contoso\svc-Exchange-Monitor"
$LogFile = "D:\ExchangeScripts\Logs\CheckMailQs.log"
$EmailFrom = "Svc-Exchange-Monitor@contoso.com"
$EmailTo = @("rafat.sumreen@contoso.com")
$SmtpServer = "exch-01.contoso.local"

#Exchange Management Shell
if (-not (Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue)) {
    try {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
        Write-Host "Exchange snap-in loaded."
    }
    catch {
        Write-Error "Failed to load Exchange snap-in: $_"
        exit 1
    }
}

#Logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append
}

#FUNCTION: Total Queues 
#Get all queues that exceed the threshold across all Mailbox servers, excluding ShadowRedundancy 
function Get-TotalQueue {
    param (
        [int]$Threshold = 100
    )
    $allQueues = @()
    $MailboxServers = Get-ExchangeServer | Where-Object { $_.ServerRole -like "*Mailbox*" }
    foreach ($server in $MailboxServers) {
        try {
            $queues = Get-Queue -Server $server.Name -ErrorAction SilentlyContinue | Where-Object { $_.DeliveryType -ne "ShadowRedundancy" }
            $allQueues += $queues
        }
        catch {
            Write-Host "Failed to query queues on $($server.Name): $_" -ForegroundColor Red
        }
    }
    $largeQueues = $Queues | Where-Object { $_.MessageCount -gt $Threshold } 
    return $largeQueues
}
#FUNCTION: Email Alert
function Send-EmailAlert {
    param ($QueueSummary)
    $htmlBody = @"
    <html><body>
    <h3>Exchange Mail Queue Alert</h3>
    <p>One or more mail queues have exceeded the threshold of <strong>$Threshold</strong> messages. Immediate investigation is required.</p>
    <pre>$QueueSummary</pre>
    </body></html>
"@
    try {
        $key = [System.IO.File]::ReadAllBytes("D:\ExchangeScripts\Creds\key.bin")
	$SecurePassword = Get-Content $SecurePasswordPath | ConvertTo-SecureString -Key $key
        $cred = New-Object System.Management.Automation.PSCredential ($UserName, $SecurePassword)
        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, 587)
        $useSSL = $True
        $smtp.Credentials = New-Object System.Net.NetworkCredential(
            $cred.UserName,
            $cred.GetNetworkCredential().Password
        )
 
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = New-Object System.Net.Mail.MailAddress($EmailFrom)
        $EmailTo | ForEach-Object { $mail.To.Add($_) }
        $mail.Subject = "Exchange Queue Alert - Threshold ($Threshold) Exceeded"
        $mail.Body = $htmlBody
        $mail.IsBodyHtml = $true
        $smtp.Send($mail)
        Write-Log "Email alert sent."
    }
    catch {
        Write-Log "Failed to send email alert: $_" "ERROR"
    }
}
#Queue Checks 
# Check for persistent queue issues- Three checks, two and one minute inervals.  
Write-Log "Starting queue monitor script..."
$FirstCheck = Get-TotalQueue
if ($FirstCheck.Count -gt 0) {
    Write-Log "Queues exceed threshold. Waiting 2 minutes..."
    Start-Sleep -Seconds 120
    $SecondCheck = Get-TotalQueue
    if ($SecondCheck.Count -gt 0 -and ($SecondCheck.Count -ge $FirstCheck.Count)) {
        Write-Log "Queues remain high or increased. Waiting 1 more minute..."
        Start-Sleep -Seconds 60
        $ThirdCheck = Get-TotalQueue
        if ($ThirdCheck.Count -gt 0 -and ($ThirdCheck.Count -ge $SecondCheck.Count)) {
            Write-Log "Persistent queue issue detected. Sending alerts..."
            $Summary = $FirstCheck | ForEach-Object { "$($_.Identity): $($_.MessageCount) messages" } | Out-String
            Send-EmailAlert -QueueSummary $Summary
        }
        else {
            Write-Log "Queues reduced in third check. No action needed."
        }
    }
    else {
        Write-Log "Queues dropped in second check. No alert sent."
    }
}
else {
    Write-Log "All queues within acceptable limits."
}
Write-Log "Queue monitor script completed."
