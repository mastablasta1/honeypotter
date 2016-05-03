@echo off

::--- Parameters

set MANAGEMENT_ACCOUNT_PASSWORD=secret
set WEBSERVER_PUBLIC_DOMAIN=blog.honeypotter.org
set PUBLIC_IP_ADDRESS=192.168.12.21
set FORWARDED_SSH_PORT=2244
set HONEYPOT_HOSTNAME=webserver

::--- End of parameters


:: =============== INTERNALS, DO NOT MODIFY ====================
setlocal EnableDelayedExpansion

set ERRORLEVEL=
set VAGRANT_BOX=ubuntu/wily64
set ROOT_DIR=%~dp0
set ROOT_DIR=%ROOT_DIR:~0,-1%
set VM_DIR_NAME=honeypot_data
set VM_DIR=%ROOT_DIR%\%VM_DIR_NAME%
set VAGRANT_FILE_PATH=%VM_DIR%\Vagrantfile
set VAGRANT_METADATA_DIR=%VM_DIR%\.vagrant
rem set VAGRANT_SNAPSHOTS_DIR=%VM_DIR%\snapshots
set PUPPET_MANIFESTS_DIR=%VM_DIR%\manifests
set LOGS_DIR_NAME=logs
set LOGS_DIR=%VM_DIR%\%LOGS_DIR_NAME%
set PUPPET_MANIFESTS_FILE=%PUPPET_MANIFESTS_DIR%\default.pp
set MANAGEMENT_ACCOUNT_NAME=management

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
if !ERRORLEVEL! NEQ 0 (
	echo Vagrant is not installed. Aborting... 1>&2
	exit /b 1
)

if "%1"=="help" ( 
	call :help
) else if "%1"=="configure" ( 
	call :configure
) else if "%1"=="destroy" ( 
	call :destroy
) else if "%1"=="start" ( 
	call :start
) else if "%1"=="stop" ( 
	call :stop
) else (
	set ERRORLEVEL=2
	echo No such command. Try '%~n0 help'.
)

if errorlevel 1 echo Error number !ERRORLEVEL!
exit /b !ERRORLEVEL!

::-------------------------------------
::-- FUNCTIONS SECTION
::-------------------------------------


::-- CONFIGURE HONEYPOT FUNCTION ---------
:configure

mkdir %VM_DIR%
if errorlevel 1 exit /b !ERRORLEVEL!
mkdir %PUPPET_MANIFESTS_DIR%
if errorlevel 1 exit /b !ERRORLEVEL!
mkdir %LOGS_DIR%
if errorlevel 1 exit /b !ERRORLEVEL!


::--- Check if VM was already created
if exist %VAGRANT_METADATA_DIR% (
	echo Honeypot was already configured in this directory. Run "destroy" command first.
	exit /b 2
)

set GUEST_LOGS_DIR=/home/%MANAGEMENT_ACCOUNT_NAME%/%LOGS_DIR_NAME%

(
	echo Vagrant.configure^(2^) do ^|config^|
	echo   config.vm.define "honeypot" do ^|honeypot^|
	echo   end
	echo   config.vm.box = "%VAGRANT_BOX%"
	echo   config.vm.hostname = "%HONEYPOT_HOSTNAME%"
	echo   config.vm.synced_folder ".", "/vagrant", disabled: true
	rem echo   config.vm.synced_folder "%LOGS_DIR:\=/%/", "/home/%MANAGEMENT_ACCOUNT_NAME%", owner: "%MANAGEMENT_ACCOUNT_NAME%", group: "%MANAGEMENT_ACCOUNT_NAME%"
	echo   config.vm.network "private_network", ip: "%PUBLIC_IP_ADDRESS%"
	echo   config.vbguest.auto_update = false
	echo   config.vm.provider "virtualbox" do ^|vb^|
	echo     vb.gui = true
	echo     vb.memory = "1024"
	echo     vb.cpus = 1
	rem echo     vb.customize ["modifyvm", :id, "--snapshotfolder", "%VAGRANT_SNAPSHOTS_DIR:\=/%"]
	echo     vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
	echo     vb.customize ["sharedfolder", "add", :id, "--name", "%LOGS_DIR_NAME%", "--hostpath", "%LOGS_DIR:\=/%"]
	echo   end
	echo   config.vm.provision "pre_puppet", type: "shell" do ^|s^|
	echo     s.inline = "sudo apt-get install whois;
	echo             wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb;
	echo             sudo dpkg -i puppetlabs-release-precise.deb;
	echo             mkdir -p /etc/puppet/modules;
	echo             puppet module install puppetlabs-apache;
	echo             puppet module install puppetlabs-mysql"
	echo   end
	echo   config.vm.provision "puppet", type: "puppet" do ^|puppet^|
	echo     puppet.manifests_path = "manifests"
	echo     puppet.manifest_file = "default.pp"
	echo   end
	echo   config.vm.provision "post_puppet", type: "shell" do ^|s^|
	echo     s.inline = "mkdir %GUEST_LOGS_DIR%;
	echo                 chown %MANAGEMENT_ACCOUNT_NAME%:%MANAGEMENT_ACCOUNT_NAME% %GUEST_LOGS_DIR%;
    echo                 mount -t vboxsf -o uid=`id -u %MANAGEMENT_ACCOUNT_NAME%`,gid=`id -g %MANAGEMENT_ACCOUNT_NAME%` %LOGS_DIR_NAME% %GUEST_LOGS_DIR%"
	echo   end
	echo end
) >%VAGRANT_FILE_PATH%

(
	echo exec { 'apt-update':
	echo 	command =^> '/usr/bin/apt-get update'
	echo }
	echo package { 'htop':
	echo 	ensure =^> installed,
	echo 	require =^> Exec['apt-update']
	echo }
	echo group { '%MANAGEMENT_ACCOUNT_NAME%':
	echo 	ensure	=^> present,
	echo }
	echo user { '%MANAGEMENT_ACCOUNT_NAME%':
	echo 	require	=^> Group['%MANAGEMENT_ACCOUNT_NAME%'],
	echo 	ensure	=^> present,
	echo 	groups	=^> ['%MANAGEMENT_ACCOUNT_NAME%','sudo','vboxsf'],
	echo 	shell	=^> '/bin/bash',
	echo 	password	=^> generate^('/bin/bash', '-c', "mkpasswd -m sha-512 %MANAGEMENT_ACCOUNT_PASSWORD% | tr -d '\n'"^),
	echo 	home	=^> '/home/%MANAGEMENT_ACCOUNT_NAME%',
	echo 	managehome	=^> true
	echo }
	echo class { 'apache':
	echo 	default_vhost	=^> false,
	echo 	mpm_module	=^> 'prefork',
	echo }
	echo class {'apache::mod::php': }
	echo apache::vhost { '%WEBSERVER_PUBLIC_DOMAIN%':
	echo 	ip	=^> '%PUBLIC_IP_ADDRESS%',	
	echo 	port	=^> '80',
	echo 	docroot	=^> '/var/www/blog',
	echo }
	echo class { 'mysql::server':
	echo 	root_password	=^> 'management',
	echo }
) >%PUPPET_MANIFESTS_FILE%

echo Created honeypot definition in: %VM_DIR%
exit /b 0
::--- END OF CONFIGURE HONEYPOT FUNCTION

::--- HELP FUNCTION
:help
echo Available commands:
echo 	configure	creates a configuration of honeypot which is then used in start/stop commands
echo.
echo 	destroy	shuts down honeypot and deletes its configuration and VM data
echo.
echo 	start	starts a honeypot (virtual machine on VirtualBox). Requires an existing honeypot configuration.
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
	echo. && echo Honeypot start failed.
	exit /b 1
)
vagrant snapshot push
exit /b 0
::--- END OF START HONEYPOT

::--- STOP HONEYPOT
:stop
pushd %VM_DIR%
vagrant halt
popd
exit /b 0
::--- END OF STOP HONEYPOT

::--- DESTROY
:destroy
setlocal EnableDelayedExpansion
if exist %VM_DIR% (
	set /P ANSWER="Are you sure you want to destroy Honeypot completely? (y/N) "
	if /I "!ANSWER!"=="Y" (
		echo Destroying...
	) else (
		exit /b 0
	)

	pushd %VM_DIR%
	vagrant destroy --force
	popd

	rmdir %VM_DIR% /S /Q
	if not errorlevel 1 echo Honeypot destroyed.
	exit /b !ERRORLEVEL!
)
echo Honeypot does not exist. Nothing to do.
exit /b 0
::--- END OF DESTROY

::--- RESTORE
:restore

exit /b 0
::--- END OF RESTORE