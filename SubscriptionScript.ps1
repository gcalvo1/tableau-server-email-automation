#Pass this parameter through the PowerShell command -config_path
param ([string] $config_path = $(''))
$ErrorActionPreference = "Stop"

#Set global variables
$TABLEAU_SERVER = #Your Tableau Server Name
$USERNAME = #Your Tableau Server Username
$PASSWORD = #Your Tableau Server Password
$SMTP_SERVER = #Your SMPT Server Name
$SMTP_SERVER_PORT = #Your SMPT Server Port
$ENABLE_SSL = #1 for SSL 0 for no SSL
$FROM = #Email address to send email from
$CURRENT_DATE_TIME = $(get-date -f 'yyyy-MM-dd hh:mm:ss')
$CURRENT_DATE = $(get-date -f 'yyyy-MM-dd')
$CURRENT_DATE_TIME_MINUS_30 = [datetime]::ParseExact($CURRENT_DATE,"yyyy-MM-dd", $null).AddDays(-29)
$LOG_FILE_PATH = #Your path to log file i.e. "C:\Users\Administrator\Documents\SubscriptionLogs\" 
$LOG_FILE_NAME = #Path with log file name i.e."C:\Users\Administrator\Documents\SubscriptionLogs\SubscriptionLog_$CURRENT_DATE.txt"

#Function to Write Message to Log File
function write-log ([string]$logtext)
{
	"$(get-date -f 'yyyy-MM-dd hh:mm:ss'): $logtext" >> $LOG_FILE_NAME
}

#Create daily log file if it doesn't already exist
if (!(Test-Path $LOG_FILE_NAME))
{
   New-Item -path $LOG_FILE_NAME -type "file"
   Write-Host "Created new file and text content added" -foreground "green"
}

#Delete log file from 30 days ago if it exists
$Log_Files = Get-ChildItem $LOG_FILE_PATH  
foreach ($file in $Log_Files)
{
	$File_Creation_Date = $file.CreationTime
	if ($File_Creation_Date -le $CURRENT_DATE_TIME_MINUS_30)
	{
		Set-Location -Path "C:\Users\Administrator\Documents\SubscriptionLogs"
		Remove-Item -path $file
		Write-Host "Cleaned up log file: $file" -foreground "green"
		write-log("Log File $file Deleted")
	}
}

#Function to set next_run_date variable based on current date
function set-next-run-date ([string]$recurrence)
{					
	if($recurrence -eq "Daily")
	{
		$next_run_date = [datetime]::ParseExact($CURRENT_DATE_TIME,"yyyy-MM-dd hh:mm:ss", $null).AddDays(1)
	}
	if($recurrence -eq "Weekly")
	{
		$next_run_date = [datetime]::ParseExact($CURRENT_DATE_TIME,"yyyy-MM-dd hh:mm:ss", $null).AddDays(7)	
	}
	if($recurrence -eq "Monthly")
	{
		$next_run_date = [datetime]::ParseExact($CURRENT_DATE_TIME,"yyyy-MM-dd hh:mm:ss", $null).AddMonths(1)	
	}
	if($recurrence -eq "Hourly")
	{
		$next_run_date = [datetime]::ParseExact($CURRENT_DATE_TIME,"yyyy-MM-dd hh:mm:ss", $null).AddHours(1)	
	}
	
	$next_run_date = $next_run_date.ToString('yyyy-MM-dd hh:mm:ss')
	
	return $next_run_date
}

#Start of the Subscription Engine Logic
write-log("Subscription Engine Started")
write-host "Subscription Engine Started" -foreground "green"

#import config and distro csv file
$csvfile_config = import-csv -path $config_path

#loop through records in config csv file
foreach ($config_line in $csvfile_config)
{
	#check if the subscription should run
	if ($config_line.next_run_date -le $(get-date -f 'yyyy-MM-dd hh:mm:ss'))
	{
		#Setting variables FROM config file
		$site = $config_line.Site
		$view_url = $config_line.View_URL		
		$save_file = $config_line.Save_File
		$file_type = $config_line.File_Type
		if ($file_type -eq "pdf") { $file_type_export = "fullpdf" } else {  $file_type_export = $file_type }
		$email_subject = $config_line.Email_Subject
		$email_body = $config_line.Email_Body
		$attach_report = $config_line.Attach_Report
		$embed_in_body = $config_line.Embed_In_Body
		$email_to = $config_line.Email_To
		$email_cc = $config_line.Email_CC
		$recurrence = $config_line.Recurrence
		$report_name = $config_line.Report_Name
		$next_run_date_config = $config_line.Next_Run_Date
		
		#Build the email address lists with email addresses from the csv config file
		if ($email_to -ne $null) 
		{	
			$email_to_array = $email_to.replace(" ","").Split("{;}")
		}
		if ($email_cc -ne $null) 
		{	
			$email_cc_array = $email_cc.replace(" ","").Split("{;}")
		}
		
		#Setup for report embedded in email body	
		if ( $embed_in_body -eq "Yes" )
		{
			$file_type = "png"
			$body = "<p>
						<a href='"+$TABLEAU_SERVER+"/#/site/"+$site+"/views/"+$view_url+"'>
							<img src='cid:Attachment' />
						</a>
						<br />
						$email_body
					</p>" 
		}
		else
		{
			$body = $email_body
		}		
				
		write-log("Subscription Started for $report_name")
		write-host "Subscription Started for $report_name" -foreground "green"
	
		#Set the file name of the file to be downloaded with timestamp
		$saved_file = "$($save_file)_$(get-date -f 'yyyy-MM-dd_hh-mm-ss').$file_type"
		$saved_file_quotes = """$($save_file)_$(get-date -f 'yyyy-MM-dd_hh-mm-ss').$file_type"""		

		#Change to the directory that has the tabcmd.exe file
		Set-Location -Path "C:\Program Files\Tableau\Tableau Server\10.4\bin"

		#Get the view and download to specified location.
		Invoke-Expression -Command: ".\tabcmd logout"
		Invoke-Expression -Command: ".\tabcmd export -t $site $view_url --$file_type_export -f $saved_file_quotes -u $USERNAME -p $PASSWORD"
		
		#Flag to ensure emails were sent before updating the next run date
		$email_success = 1
		
		Try
		{
			#Creating a Mail object
			$msg = new-object Net.Mail.MailMessage
			$attach = new-object Net.Mail.Attachment("$saved_file")
			$attach_embed = new-object Net.Mail.Attachment("$saved_file")
			$attach_embed.ContentType.MediaType = "image/png"
			$attach_embed.ContentId = "Attachment"
			#Creating SMTP server object
			$emailUSERNAME = "AKIAIC5T5BTGXIQ3PZEQ"
			$encrypted = Get-Content C:\Users\Administrator\Documents\encrypted_smtp_PASSWORD.txt | ConvertTo-SecureString
			$smtp = new-object Net.Mail.SmtpClient($SMTP_SERVER,$SMTP_SERVER_PORT)
			$smtp.Credentials = New-Object System.Management.Automation.PsCredential($emailUSERNAME, $encrypted)
			$smtp.Timeout = 1000000
			if ($ENABLE_SSL -eq 1)
				{$smtp.enablessl = $true}
						
			#Email structure 
			$msg.FROM = $FROM			
			$to_list = ""
			$cc_list = ""
			
			if ($email_to_array -ne $null)
			{
				foreach ($addr in $email_to_array)
				{
					$msg.To.Add($addr)
					$to_list = "$to_list $addr;"
				} 
			}
			if ($email_cc_array -ne $null)
			{
				foreach ($addr in $email_cc_array)
				{
					$msg.cc.Add($addr)
					$cc_list = "$cc_list $addr;"
				} 
			}
						 
			$msg.subject = $email_subject
			if ($embed_in_body -eq "Yes") { $msg.Attachments.add($attach_embed) }
			if ($attach_report -eq "Yes") { $msg.Attachments.add($attach) }
			$msg.body = $body  
			$msg.IsBodyHTML = $true
			write-log("Email Execution of $report_name to $to_list Started")
			#Sending email 
			#$smtp.Send($msg)
			write-log("Email Successfully sent.")
			#cleans up file locks on downloaded file
			$attach.dispose()
			$attach_embed.dispose()
			$msg.dispose()
			write-log("$report_name Subscription to To: $to_list CC: $cc_list Complete")
			write-host "Email Complete for $report_name" -foreground "green"
		}
		Catch
		{
			#Creating error Mail object
			$error_msg = new-object Net.Mail.MailMessage
			#Creating error SMTP server object
			$error_smtp = new-object Net.Mail.SmtpClient($SMTP_SERVER,$SMTP_SERVER_PORT)
			$emailUSERNAME = "AKIAIC5T5BTGXIQ3PZEQ"
			$encrypted = Get-Content C:\Users\Administrator\Documents\encrypted_smtp_PASSWORD.txt | ConvertTo-SecureString
			$error_smtp.Credentials = New-Object System.Management.Automation.PsCredential($emailUSERNAME, $encrypted)
			$error_smtp.Timeout = 1000000
			if ($ENABLE_SSL -eq 1)
				{$error_smtp.enablessl = $true}
					
			#Email structure 
			$error_msg.FROM = $FROM
			$error_msg.To.Add(#Email address to send error message to)
			$error_msg.subject = "TABLEAU TESTING ERROR HANDLING - $report Subscription Failure"
			$error_msg.body = "$report_name failed to send to To: $to_list CC: $cc_list With Error: $_"
			#Sending email 
			#$smtp.Send($error_msg)
			$error_msg.dispose()
			$email_success = 0
			write-log("$report_name Subscription to $message_to Failed With Error: $_")
			write-host "Error: $report_name failed to send to To: $to_list CC: $cc_list With Error: $_" -foreground "red"					
		}	
		
		#If emails were sent successfully, update CSV config with new next run date
		if ($email_success -eq 1)
		{
			#If the report is not scheduled to run hourly, we want to update the date but not the time of execution
			if ($recurrence -ne "Hourly")
			{
				$next_run_date = set-next-run-date($recurrence)
				$next_run_date = $next_run_date.Substring(0,10)
				$next_run_hour = $next_run_date_config.Substring($next_run_date_config.IndexOf(" ")+1)
				$next_run_date = "$next_run_date $next_run_hour"
				$config_line.next_run_date = $next_run_date
			}
			#If the report is scheduled to run hourly, we want to increment the hour of execution by 1
			else
			{
				$next_run_date = set-next-run-date($recurrence) 
				$config_line.next_run_date = $next_run_date
			}
			
			$csvfile_config | Select Report_Name, Site, View_URL, Save_File, File_Type, Email_Subject, Email_Body, Attach_Report, Embed_In_Body, Email_To, Email_CC, Recurrence, Next_Run_Date | Export-CSV -Path $config_path -Encoding ASCII -NoTypeInformation
			write-log("Next Run Date Update Complete for $report_name. Next Run Date: $next_run_date")
			write-host "Next Run Date Update Complete for $report_name. Next Run Date: $next_run_date" -foreground "green"
		}
		else
		{
			write-host "Next Run Date NOT Updated for $report_name Because of Email Sending Error" -foreground "red"
			write-log("Next Run Date NOT Updated for $report_name Because of Email Sending Error")
		}
		
		Invoke-Expression -Command: ".\tabcmd logout"

		write-log("Subscription Complete for $report_name")
		write-host "Subscription Complete for $report_name" -foreground "green"	
	}
}

write-log("Subscription Engine Complete")
write-host "Subscription Engine Complete" -foreground "green"