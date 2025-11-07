Readme for clean user profile

1. Copy cleanprofile.ps1 to C:\Temp on target computer using Admin share

2. The script cleans up user profiles that are inactive for 1 day by default, you can manually change it on Line 6
	$daysInactive = (no. of days inactive)
   
3. On Endpoint Command Prompt, run 
	powershell.exe -ExecutionPolicy Bypass -File "C:\Temp\cleanprofile.ps1"
	
4. Admin can also download PSExec and run the PowerShell remotely from admin's Command Prompt using
"C:\Tools\PSTools\PsExec.exe" \\JC0XXXX -s -d powershell.exe -ExecutionPolicy Bypass -File "C:\Temp\cleanprofile.ps1"
	- Assuming your PsExec.exe is downloaded into C:\Tools\PSTools folder
	- Run cmd as admin in admin's computer
	- \\JC0XXXX is the target computer's hostname
