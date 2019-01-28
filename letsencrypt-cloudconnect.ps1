##
## Let's Encrypt for Veeam Cloud Connect
##
## Version 2.0
##
## Author Luca Dell'Oca
##


### INITIALIZATION ###

# This script uses Powershell Gallery if you have at least Powershell 5.0.
# This script has been developed with ACMESharp 0.9.1.326

Set-ExecutionPolicy unrestricted

# Load ACMESharp module

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


# Change to the Vault folder. Create it if it doesn't exist

$path = "C:\ProgramData\ACMESharp\sysVault"
If(!(test-path $path))
{
      New-Item -ItemType Directory -Force -Path $path
}

cd C:\ProgramData\ACMESharp\sysVault

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


### PART 1: UPDATE THE IDENTIFIER ###

New-ACMEIdentifier -Dns $domain -Alias $alias
Complete-ACMEChallenge $alias -ChallengeType dns-01 -Handler manual

(Update-ACMEIdentifier $alias -ChallengeType dns-01).Challenges | Where-Object {$_.Type -eq "dns-01"} > challenge.txt
$RRtext = Select-String challenge.txt -Pattern "RR " -CaseSensitive | select Line | Out-String

# Here we grab the new TXT DNS Record and output in a message box.
# In this way we have all the time to go and edit the DNS server before
# we continue with the script.

# add the required .NET assembly for the MessageBox
Add-Type -AssemblyName System.Windows.Forms

$msgBoxInput =  [System.Windows.Forms.MessageBox]::Show($RRtext,'Update your DNS with this TXT record, Use CTRL+C to get the text','OK','Information')

 switch  ($msgBoxInput) {
 'OK' {

Submit-ACMEChallenge $alias -ChallengeType dns-01
Update-ACMEIdentifier $alias

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
