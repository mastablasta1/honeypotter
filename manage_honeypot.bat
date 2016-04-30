@echo off

::--- Parameters
set VM_DIR_NAME=honeypot_data
set VAGRANT_BOX=puppetlabs/ubuntu-14.04-64-puppet
::--- End of parameters


set ROOT_DIR=%~dp0
set ROOT_DIR=%ROOT_DIR:~0,-1%
set VM_DIR=%ROOT_DIR%\%VM_DIR_NAME%
set VAGRANT_FILE_PATH=%VM_DIR%\Vagrantfile
set VAGRANT_METADATA_DIR=%VM_DIR%\.vagrant
set VAGRANT_SNAPSHOTS_DIR=%VM_DIR%\snapshots

echo Honeypotter 0.1
echo.

if [%1]==[] (
	echo Syntax: %~n0 COMMAND
	echo.
	call :help
	exit /b 2
)

::--- Check if vagrant is installed
WHERE vagrant >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
	echo Vagrant is not installed. Aborting... 1>&2
	exit /b 1
)

if "%1"=="help" call :help
if "%1"=="create" call :create
if "%1"=="delete" call :delete

exit /b %ERRORLEVEL%

::-------------------------------------
::-- FUNCTIONS SECTION
::-------------------------------------


::-- CREATE HONEYPOT FUNCTION ---------
:create

mkdir %VM_DIR%
if errorlevel 1 exit /b %ERRORLEVEL%
mkdir %VAGRANT_SNAPSHOTS_DIR%
if errorlevel 1 exit /b %ERRORLEVEL%

::--- Check if VM was already created
if exist %VAGRANT_METADATA_DIR% (
	echo Honeypot was already created. To create new honeypot, run "delete_honeypot.bat" first.
	exit /b 2
)

(
	echo Vagrant.configure^(2^) do ^|config^|
	echo   config.vm.box = "%VAGRANT_BOX%"
	echo   config.vm.network "forwarded_port", guest: 80, host: 8080
	echo   config.vm.network "private_network", ip: "192.168.23.32"
	echo   config.vm.provider "virtualbox" do ^|vb^|
	echo     vb.gui = true
	echo     vb.linked_clone = true
	echo     vb.customize ["modifyvm", :id, "--snapshotfolder", "%VAGRANT_SNAPSHOTS_DIR%"]
	echo   end
	echo   config.vm.provision "shell", 
	echo     inline: "wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb;
	echo             sudo dpkg -i puppetlabs-release-precise.deb;
	echo             mkdir -p /etc/puppet/modules;
	echo             puppet module install puppetlabs-apache;
	echo             puppet module install puppetlabs-mysql"
	rem echo   config.vm.provision "puppet" do ^|puppet^|
	rem echo     puppet.manifests_path = "manifests"
	rem echo     puppet.manifest_file = "default.pp"
	rem echo   end
	echo end
) >%VAGRANT_FILE_PATH%

echo Created honeypot definition in: %VM_DIR%
exit /b 0
::--- END OF CREATE HONEYPOT FUNCTION

::--- HELP FUNCTION
:help
echo Available commands:
echo 	create	creates a definition of honeypot in the location of this script
echo.
echo 	delete	deletes honeypot existing in a directory
echo.
echo 	start	starts a honeypot (virtual machine on VirtualBox). Requires an existing honeypot definition.
echo.
echo 	help	displays this help
exit /b 0
::--- END OF HELP FUNCTION

::--- DELETE FUNCTION
:delete
if exist %VM_DIR% (
	rmdir %VM_DIR% /S /Q
	if not errorlevel 1 echo Honeypot deleted.
	exit /b %ERRORLEVEL%
)
echo Honeypot definition does not exist. Nothing to do.
exit /b 0
::--- END OF DELETE FUNCTION