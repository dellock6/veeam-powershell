##
## Let's Encrypt for Veeam Cloud Connect
##
## This script automates the creation and retrieval of Let's Encrypt certificates
## using AWS Route53 as a challenge mechanism, and then installs the certificates
## in Veeam Cloud Connect.
##
## Version 3.0 - 2019-01-28
##
## Author Luca Dell'Oca
##
## This script uses Powershell Gallery, so you need at least Powershell 5.0.
## This script has been developed with ACMESharp 0.9.1.326
## Please execute it on the Veeam Cloud Connect server.

### VARIABLES ###

# alias for the ACME request.
# As long as you don't run more than one request per day, this is correct.
# Otherwise, plan to add also hours and minutes to make your requests unique.
$alias = "vcc-$(get-date -format yyyyMMdd)"

# Let's Encrypt certificates expire after 90 days, so you will have many of them in the local
# certificate store after some time. It's easier to identify them if we give them a unique name.
# We use the date here to do so.
$certname = "vcc-$(get-date -format yyyyMMdd)"

# Give a name to the PFX file on disk, based on the certificate name
$pfxfile = "C:\ProgramData\ACMESharp\sysVault\$certname.pfx"

# Store the certificates into the Local Store of the Local Machine account
$certPath = "\localMachine\my"

# Configure the FQDN that the certificate needs to be binded to
$domain = "cc.virtualtothecore.com"

# Give a friendly name to the certificate so that it can be identified in the certificate store
$friendlyname = "letsencrypt-$(get-date -format yyyyMMdd)"

# Set the email used to register with Let's Encrypt service
$contactmail = "ldelloca@gmail.com"


### INITIALIZATION ###

Set-ExecutionPolicy unrestricted - Force

# Load Powershell modules

function Load-Module ($m) {

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m -Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Verbose -Scope CurrentUser
                Import-Module $m -Verbose
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $m not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }
}

Load-Module "ACMESharp"
Load-Module "AWSPowerShell"

# Change to the Vault folder. Create it if it doesn't exist.

$path = "C:\ProgramData\ACMESharp\sysVault"

If(!(test-path $path))
{
      New-Item -ItemType Directory -Force -Path $path
}

cd $path


# Initialize the Vault if it's a fresh new install, otherwise move on

  #Check if a vault already exists
  write-host "Check if a vault already exists..."
  $Vault = Get-ACMEVault
  if (!$Vault)
   {
    write-host "No vault found, trying to create new vault..."
    $CreateVault = Initialize-ACMEVault
    sleep 1
    $Vault = Get-ACMEVault
    if (!$Vault)
     {
      write-host "Error: Vault could not be created" -foregroundcolor red
     exit
     }
   }

#Check if Let's Encrypt registry is present
  write-host "Check Let's Encrypt Registration..."
  $Registration = Get-ACMERegistration
  if (!$Registration)
   {
    write-host "Warning: No registration was found at Let's Encrypt, new registration is being performed" -foregroundcolor yellow
    $Registration = New-ACMERegistration -Contacts mailto:$contactmail -AcceptTos
    if (!$Registration)
     {
      write-host "Error: Could not register with Let's Encrypt" -foregroundcolor red
   exit
     }
    else
     {
      write-host "Registration at Let's Encrypt was done" -foregroundcolor green
     }
   }


### PART 1: UPDATE THE IDENTIFIER ###

New-ACMEIdentifier -Dns $domain -Alias $alias
Complete-ACMEChallenge $alias -ChallengeType dns-01 -Handler manual

# Writes the new DNS challenge into a text file
(Update-ACMEIdentifier $alias -ChallengeType dns-01).Challenges | Where-Object {$_.Type -eq "dns-01"} > challenge.txt

# Get the new TXT record from Let's Encrypt
$RRtext = Select-String challenge.txt -Pattern "RR Value" -CaseSensitive | Out-String -Stream
$separator = "["
$RRtext = $RRtext.split($separator)
$RRtext = $RRtext[2]
$RRtext = $RRtext.trimend("]")
$RRtext = """$RRtext"""

# Update the TXT Resource Record in AWS Route53

$change = New-Object Amazon.Route53.Model.Change
$change.Action = "UPSERT"
$change.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
$change.ResourceRecordSet.Name = "_acme-challenge.cc.virtualtothecore.com."
$change.ResourceRecordSet.Type = "TXT"
$change.ResourceRecordSet.TTL = 300
$change.ResourceRecordSet.ResourceRecords = (New-Object Amazon.Route53.Model.ResourceRecord($RRtext))

$params = @{
    HostedZoneId="ZQUSU6S6339VA"
	ChangeBatch_Comment="Updated TXT record for cc.virtualtothecore.com. with new Let'sEncrypt challenge"
	ChangeBatch_Change=$change
}

Edit-R53ResourceRecordSet @params


### PART 2: UPDATE THE CERTIFICATE ###

# Generate a new certificate
New-ACMECertificate ${alias} -Generate -Alias $certname

# Submit the certificate request
Submit-ACMECertificate $certname

# Wait until the certificate is available (has a serial number) before moving on
# as API work in async mode so the cert may not be immediately released.

$serialnumber = $null
$serialnumber = $(update-AcmeCertificate $certname).SerialNumber

# Export the new Certificate to a PFX file
Get-ACMECertificate $certname -ExportPkcs12 $pfxfile

# Import Certificate into Certificate Store
Import-PfxCertificate -CertStoreLocation cert:\localMachine\my -Exportable -FilePath $pfxfile

### PART 3: INSTALL THE CERTIFICATE INTO VEEAM CLOUD CONNECT

asnp VeeamPSSnapin
Connect-VBRServer -Server localhost
$certificate = Get-VBRCloudGatewayCertificate -FromStore | Where {$_.SerialNumber -eq $serialnumber}
Add-VBRCloudGatewayCertificate -Certificate $certificate
Disconnect-VBRServer

}
}

Return

### SCRIPT END ###
