# veeam-powershell

This is a collection of some Powershell scripts I created.

**letsencrypt-cloudconnect-aws.ps1**

This script automates the creation and retrieval of Let's Encrypt certificates using AWS Route53 as a challenge mechanism, and then installs the certificates in Veeam Cloud Connect.


**letsencrypt-cloudconnect.ps1**

Old version of the script that doesn't use any automatic challenge mechanism. You can use it to complete a manual DNS challenge thanks to the pop-up dialog that makes it easy to copy-paste the TXT resource records coming from Let's Encrypt.


**dynamic-surebackup.ps1**

Allows you to run Veeam Surebackup against a given number of virtual machines per day, and to test thousands of them over time.


**veeam-backupjob-creator.ps1**

Simple script that can be used as an example to create Veeam Backup jobs.
