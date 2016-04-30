@echo off
setlocal

::--- Parameters
set MANAGEMENT_PASSWORD=management
set VM_DIR_NAME=honeypot_data
set VAGRANT_BOX=ubuntu/trusty64
::set VAGRANT_BOX=puppetlabs/ubuntu-14.04-64-puppet
::--- End of parameters

set ERRORLEVEL=
set ROOT_DIR=%~dp0
set ROOT_DIR=%ROOT_DIR:~0,-1%
set VM_DIR=%ROOT_DIR%\%VM_DIR_NAME%
set VAGRANT_FILE_PATH=%VM_DIR%\Vagrantfile
set VAGRANT_METADATA_DIR=%VM_DIR%\.vagrant
set VAGRANT_SNAPSHOTS_DIR=%VM_DIR%\snapshots
set PUPPET_MANIFESTS_DIR=%VM_DIR%\manifests
set PUPPET_MANIFESTS_FILE=%PUPPET_MANIFESTS_DIR%\default.pp

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

if "%1"=="help" ( 
	call :help
) else if "%1"=="create" ( 
	call :create
) else if "%1"=="destroy" ( 
	call :destroy
) else if "%1"=="start" ( 
	call :start
) else (
	set ERRORLEVEL=2
	echo No such command. Try '%~n0 help'.
)

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
mkdir %PUPPET_MANIFESTS_DIR%
if errorlevel 1 exit /b %ERRORLEVEL%

::--- Check if VM was already created
if exist %VAGRANT_METADATA_DIR% (
	echo Honeypot was already created. To create new honeypot, run "delete" command first.
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
	echo     inline: "sudo apt-get install whois;
	echo             wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb;
	echo             sudo dpkg -i puppetlabs-release-precise.deb;
	echo             mkdir -p /etc/puppet/modules;
	echo             puppet module install puppetlabs-apache;
	echo             puppet module install puppetlabs-mysql"
	echo   config.vm.provision "puppet" do ^|puppet^|
	echo     puppet.manifests_path = "manifests"
	echo     puppet.manifest_file = "default.pp"
	echo   end
	echo end
) >%VAGRANT_FILE_PATH%

(
	rem echo exec { 'apt-update':
	rem echo 	command => '/usr/bin/apt-get update'
	rem echo }
	echo.
	echo group { 'management':
	echo 	ensure	=^> present,
	echo }
	echo.
	echo user { 'management':
	echo 	ensure	=^> present,
	echo 	groups	=^> 'management',
	echo 	shell	=^> '/bin/bash',
	echo 	password	=^> generate^('/bin/bash', '-c', "mkpasswd -m sha-512 %MANAGEMENT_PASSWORD% | tr -d '\n'"^),
	echo 	home	=^> '/home/management',
	echo 	managehome	=^> true
	echo }
) >%PUPPET_MANIFESTS_FILE%

echo Created honeypot definition in: %VM_DIR%
exit /b 0
::--- END OF CREATE HONEYPOT FUNCTION

::--- HELP FUNCTION
:help
echo Available commands:
echo 	create	creates a definition of honeypot in the location of this script
echo.
echo 	destroy	shuts down honeypot and deletes its definition and VM data
echo.
echo 	start	starts a honeypot (virtual machine on VirtualBox). Requires an existing honeypot definition.
echo.
echo 	stop	stops a running honeypot virtual machine.
echo.
echo 	help	displays this help
exit /b 0
::--- END OF HELP FUNCTION

::--- START HONEYPOT
:start
pushd %VM_DIR%
vagrant up
if errorlevel 1 (
	echo.
	echo Honeypot start failed.
)
popd
exit /b %ERRORLEVEL%
::--- END OF START HONEYPOT

::--- STOP HONEYPOT
:stop
exit /b 0
::--- END OF STOP HONEYPOT

::--- DESTROY
:destroy
if exist %VM_DIR% (
	pushd %VM_DIR%
	vagrant destroy --force
	popd

	rmdir %VM_DIR% /S /Q
	if not errorlevel 1 echo Honeypot destroyed.
	exit /b %ERRORLEVEL%
)
echo Honeypot does not exist. Nothing to do.
exit /b 0
::--- END OF DESTROY