:: --- Created by Tomasz Idziak, Malgorzata Ciesla ---
:: --- LGPL License ---

@echo off

::--- Parameters

set MANAGEMENT_ACCOUNT_PASSWORD=secret
set PUBLIC_IP_ADDRESS=192.168.12.21
set HONEYPOT_HOSTNAME=webserver
set PUTTY_EXE_PATH="C:\Program Files (x86)\PuTTY\putty.exe"

::--- End of parameters


:: =============== INTERNALS, DO NOT MODIFY ====================
setlocal EnableDelayedExpansion

set ERRORLEVEL=
set VAGRANT_BOX=ubuntu/trusty64
set ROOT_DIR=%~dp0
set ROOT_DIR=%ROOT_DIR:~0,-1%
set VM_DIR_NAME=honeypot_data
set VM_DIR=%ROOT_DIR%\%VM_DIR_NAME%
set VAGRANT_FILE_PATH=%VM_DIR%\Vagrantfile
set VAGRANT_METADATA_DIR=%VM_DIR%\.vagrant
set PUPPET_MANIFESTS_DIR=%VM_DIR%\puppet
set PUPPET_MANIFESTS_FILE=%PUPPET_MANIFESTS_DIR%\init.pp
set LOGS_DIR_NAME=logs
set LOGS_DIR=%VM_DIR%\%LOGS_DIR_NAME%
set MANAGEMENT_ACCOUNT_NAME=management
set RSYNCD_HOST_PATH=%VM_DIR%\rsyncd.sh
set RSYNCD_GUEST_SCRIPT_PATH=./rsyncd.sh

set MONITORED_FOLDERS_FILE=%VM_DIR%\monitored
set MONITORED_FOLDERS_FILE_GUEST=./monitored

set MONITOR_SCRIPT_FILE_HOST=%VM_DIR%\monitor.sh
set MONITOR_SCRIPT_FILE_GUEST=./monitor.sh

echo.Honeypotter 0.1
echo.

if [%1]==[] (
	echo.Syntax: %~n0 COMMAND
	echo.
	call :help
	exit /b 2
)

::--- Check if vagrant is installed
WHERE vagrant >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
	echo.Vagrant is not installed. Aborting... 1>&2
	exit /b 1
)

if "%1"=="help" ( 
	call :help
) else if "%1"=="configure" ( 
	call :configure %*
) else if "%1"=="destroy" ( 
	call :destroy %*
) else if "%1"=="start" ( 
	call :start %*
) else if "%1"=="stop" ( 
	call :stop %*
) else if "%1"=="save" ( 
	call :save %*
) else if "%1"=="revert" ( 
	call :revert %*
) else if "%1"=="ssh" ( 
	call :ssh %*
) else if "%1"=="monitor" ( 
	call :monitor %*
) else (
	set ERRORLEVEL=2
	echo.No such command. Try '%~n0 help'.
)

if errorlevel 1 echo.Error number !ERRORLEVEL!
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

:_configure_iter_args
if not "%~1" == "" (
	if "%~1" == "--no-services" set NOSERVICES=true
	shift
	goto _configure_iter_args
)

::--- Check if VM was already created
if exist %VAGRANT_METADATA_DIR% (
	echo.Honeypot was already configured in this directory. Run "destroy" command first.
	exit /b 2
)

set GUEST_LOGS_DIR=/home/%MANAGEMENT_ACCOUNT_NAME%/%LOGS_DIR_NAME%
set GUEST_APACHE_LOGS_DIR_SRC=/var/log/apache2
set GUEST_APACHE_LOGS_DIR_DEST=%GUEST_LOGS_DIR%/apache
set GUEST_MYSQL_LOGS_DIR_SRC=/var/log/mysql
set GUEST_MYSQL_LOGS_DIR_DEST=%GUEST_LOGS_DIR%/mysql
set FS_MONITOR_LOG=%GUEST_LOGS_DIR%/fs_monitor.log

(
	echo.Vagrant.configure^(2^) do ^|config^|
	echo.  config.vm.define "honeypot" do ^|honeypot^|
	echo.  end
	echo.  config.vm.box = "%VAGRANT_BOX%"
	echo.  config.vm.hostname = "%HONEYPOT_HOSTNAME%"
	echo.  config.vm.synced_folder ".", "/vagrant", disabled: true
	echo.  config.vm.network "private_network", ip: "%PUBLIC_IP_ADDRESS%"
	echo.  config.vm.provider "virtualbox" do ^|vb^|
	echo.    vb.gui = true
	echo.    vb.memory = "1024"
	echo.    vb.cpus = 1
	echo.    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
	echo.    vb.customize ["sharedfolder", "add", :id, "--name", "%LOGS_DIR_NAME%", "--hostpath", "%LOGS_DIR:\=/%"]
	echo.  end
	echo.  config.vm.provision "pre_puppet", type: "shell" do ^|s^|
	echo.    s.inline = "sudo apt-get install whois;
	echo.                wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb;
	echo.                dpkg -i puppetlabs-release-trusty.deb;
	echo.                mkdir -p /etc/puppet/modules;
	echo.                puppet module install puppetlabs-apache;
	echo.                puppet module install puppetlabs-mysql;
	echo.                chmod o-rx /home/*"
	echo.  end
	echo.  config.vm.provision "puppet", type: "puppet" do ^|puppet^|
	echo.    puppet.manifests_path = "puppet"
	echo.    puppet.manifest_file = "init.pp"
	echo.  end
	echo.  config.vm.provision "rsyncd", type: "file", source: "%RSYNCD_HOST_PATH:\=/%", destination: "%RSYNCD_GUEST_SCRIPT_PATH%"
	echo.  config.vm.provision "run_always", type: "shell", run: "always" do ^|s^|
	echo.    s.inline = "mkdir --parents %GUEST_LOGS_DIR%;
	echo.                chown %MANAGEMENT_ACCOUNT_NAME%:%MANAGEMENT_ACCOUNT_NAME% %GUEST_LOGS_DIR%;
    echo.                mount -t vboxsf -o uid=`id -u %MANAGEMENT_ACCOUNT_NAME%`,gid=`id -g %MANAGEMENT_ACCOUNT_NAME%` %LOGS_DIR_NAME% %GUEST_LOGS_DIR%;
	echo.                dos2unix %RSYNCD_GUEST_SCRIPT_PATH%;
	echo.                chmod u+x %RSYNCD_GUEST_SCRIPT_PATH%;
	echo.                mkdir --parents %GUEST_APACHE_LOGS_DIR_DEST%;
	echo.                mkdir --parents %GUEST_MYSQL_LOGS_DIR_DEST%;
	echo.                %RSYNCD_GUEST_SCRIPT_PATH% %GUEST_APACHE_LOGS_DIR_SRC% %GUEST_APACHE_LOGS_DIR_DEST%;
	echo.                %RSYNCD_GUEST_SCRIPT_PATH% %GUEST_MYSQL_LOGS_DIR_SRC% %GUEST_MYSQL_LOGS_DIR_DEST%"
	echo.  end
	echo.  config.vm.provision "monitor_copy", type: "file", source: "%MONITOR_SCRIPT_FILE_HOST:\=/%", destination: "%MONITOR_SCRIPT_FILE_GUEST%"
	echo.  
	echo.  config.vm.provision "monitored_copy", type: "file", run: "always", source: "%MONITORED_FOLDERS_FILE:\=/%", destination: "%MONITORED_FOLDERS_FILE_GUEST%"
	echo.  config.vm.provision "monitor_run", type: "shell", run: "always" do ^|s^|
	echo.    s.inline = "chmod u+x %MONITOR_SCRIPT_FILE_GUEST%;
	echo.                dos2unix %MONITORED_FOLDERS_FILE_GUEST%;
	echo.                dos2unix %MONITOR_SCRIPT_FILE_GUEST%;
	echo.                touch %FS_MONITOR_LOG%;
	echo.                %MONITOR_SCRIPT_FILE_GUEST% %MONITORED_FOLDERS_FILE_GUEST% %FS_MONITOR_LOG%"
	echo.  end
	echo.end
) >%VAGRANT_FILE_PATH%

(
	echo.package { 'htop':
	echo.	ensure =^> installed,
	echo.}
	echo.package { 'dos2unix':
	echo.	ensure =^> installed,
	echo.}
	echo.package { 'inotify-tools':
	echo.	ensure =^> installed,
	echo.}
	echo.user { '%MANAGEMENT_ACCOUNT_NAME%':
	echo.	ensure	=^> present,
	echo.	groups	=^> ['sudo','vboxsf'],
	echo.	shell	=^> '/bin/bash',
	echo.	password	=^> generate^('/bin/bash', '-c', "mkpasswd -m sha-512 %MANAGEMENT_ACCOUNT_PASSWORD% | tr -d '\n'"^),
	echo.	home	=^> '/home/%MANAGEMENT_ACCOUNT_NAME%',
	echo.	managehome	=^> true
	echo.}
	echo.user { 'vagrant':
	echo.	password =^> '*'
	echo.}
	echo.exec { 'add-group':
	echo.	require =^> User['%MANAGEMENT_ACCOUNT_NAME%'],
	echo.	command =^> '/usr/sbin/usermod -g %MANAGEMENT_ACCOUNT_NAME% %MANAGEMENT_ACCOUNT_NAME%'
	echo.}
) >%PUPPET_MANIFESTS_FILE%

if !NOSERVICES! == true (
	echo.Skipping services.
	goto _no_services
)

(
	echo.exec { 'apt-update':
	echo.	command =^> '/usr/bin/apt-get update'
	echo.}
	echo.package { 'apache2':
	echo.	ensure =^> installed,
	echo.	require =^> Exec['apt-update']
	echo.}
	echo.package { 'mysql-server':
	echo.	ensure =^> installed,
	echo.	require =^> Package['apache2']
	echo.}
	echo.package { 'php5-mysql':
	echo.	ensure =^> installed,
	echo.	require =^> Package['mysql-server']
	echo.}
	echo.exec { 'mysql-restart':
	echo.	require =^> Package['php5-mysql'],
	echo.	command =^> '/usr/sbin/service mysql restart'
	echo.}
	echo.package { 'postfix':
	echo.	ensure =^> installed,
	echo.	require =^> Exec['apt-update']
	echo.}
	echo.package { 'vsftpd':
	echo.	ensure =^> installed,
	echo.	require =^> Exec['apt-update']
	echo.}
) >> %PUPPET_MANIFESTS_FILE%

:_no_services

(
	echo.#^^!/bin/bash
	echo.SRC="$1"
	echo.DEST="$2"
	echo.PID_FILE=$DEST/.rsyncd
	echo.if ^^! [ -r "$SRC" ]; then echo rsyncd no-src $SRC; exit 0; fi
	echo.if ^^! [ -w "$DEST" ]; then echo rsyncd no-dest $DEST; exit 0; fi
	echo.if [ -e "$PID_FILE" ]; then
	echo.	EPID=`cat $PID_FILE`
	echo.	if ps -p $EPID ^> /dev/null; then
	echo.		echo rsyncd already-running $EPID
	echo.		exit 0
	echo.	fi
	echo.fi
	echo.echo rsyncd start $SRC $DEST
	echo.rsync -r $SRC $DEST
	echo.nohup inotifywait -r -m -e modify $SRC ^| while read info ; do rsync -r $SRC $DEST ; done ^&
	echo.echo $^^! ^> $PID_FILE
	echo.sleep 1
) >%RSYNCD_HOST_PATH%

(
	echo.#^^!/bin/bash
	echo.MON_PATH="$1"
	echo.LOG_FILE="$2"
	echo.PID_FILE=".monitor_pid"
	echo.if [ "$#" -ne 2 ]; then
	echo.		echo monitor wrong-num-args
	echo.		exit 0
	echo.fi
	echo.if ^^! [ -r "$MON_PATH" ]; then
	echo.		echo monitor no-monitored-list $MON_PATH
	echo.		exit 0
	echo.fi
	echo.if [ -e "$PID_FILE" ]; then
	echo.	EPID=`cat $PID_FILE`
	echo.	if ps -p $EPID ^> /dev/null; then
	echo.		kill -9 $EPID
	echo.	fi
	echo.fi
	echo.^> .monitored
	echo.while read path
	echo.do
	echo.		if [ -r "$path" ]; then
	echo.				echo $path ^>^> .monitored
	echo.		fi
	echo.done ^< $MON_PATH
	echo.touch $LOG_FILE
	echo.nohup inotifywait -r -m --format '%%T %%e %%w %%f' --timefmt '%%Y-%%m-%%d %%H:%%M:%%S' --fromfile .monitored ^>^>$LOG_FILE ^&
	echo.echo $^^! ^> $PID_FILE
	echo.sleep 1
) >%MONITOR_SCRIPT_FILE_HOST%
    
type NUL > %MONITORED_FOLDERS_FILE%

echo.Created honeypot definition in: %VM_DIR%
exit /b 0
::--- END OF CONFIGURE HONEYPOT FUNCTION

::--- HELP FUNCTION
:help
echo.Available commands:
echo.	configure	- creates a configuration of honeypot which is then used in start/stop commands.
echo.		option: [--no-services]
echo.
echo.	destroy		- shuts down honeypot and deletes its configuration and VM data.
echo.
echo.	start	- starts a honeypot (virtual machine on VirtualBox). Requires an existing honeypot configuration.
echo.
echo.	stop	- stops honeypot virtual machine.
echo.
echo.	save	- saves current state of honeypot (uses "vagrant snapshot push").
echo.
echo.	revert	- restores honeypot to latest saved state (uses "vagrant snapshot pop").
echo.
echo.	monitor path1 [^path2^] ... - enable filesystem events monitoring for given folders on guest. 
echo.
echo.	ssh	- connect to virtual machine with Putty. Correct putty path in script properties is required.
echo.
echo.	help	- displays this help.
exit /b 0
::--- END OF HELP FUNCTION

::--- START HONEYPOT
:start

if not exist %VAGRANT_FILE_PATH% echo Honeypot configuration does not exist. Run '%~n0 configure' first. && exit /b 1

call :_vm_exists
if not errorlevel 1 set EXISTS=true

pushd %VM_DIR%
vagrant up
if errorlevel 1 (
	echo. && echo.Honeypot start failed.
	exit /b 2
)

if "!EXISTS!"=="true" goto _start_end

echo. && echo.Honeypot has been created. VM snapshot will now be created in case you'd like to revert your honeypot to out-of-the-box state.

vagrant snapshot push
if errorlevel 1 (
	echo. && echo.Honeypot deployed successfully, but saving state failed. You can retry with ""
	exit /b 3
)

:_start_end

popd
echo. && echo.Honeypot is ready.
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

if not exist %VM_DIR% (
	echo.Honeypot does not exist. Nothing to do.
	exit /b 0
)

set /P ANSWER="Are you sure you want to destroy Honeypot completely? Configuration will also be deleted. (y/N) "
if /I "!ANSWER!"=="Y" (
	echo.
) else (
	exit /b 0
)

if not exist %VAGRANT_METADATA_DIR% goto _destroy_remove_data

echo.Destroying honeypot VM...
pushd %VM_DIR%
vagrant destroy --force
popd
timeout /t 3 /nobreak > NUL

:_destroy_remove_data

echo.Removing configuration...
rmdir %VM_DIR% /S /Q
if not errorlevel 1 echo.Honeypot destroyed.
exit /b !ERRORLEVEL!
::--- END OF DESTROY

::--- REVERT
:revert
echo.Attempting revert to previously saved state...
pushd %VM_DIR%
:: add --no-provision after bugfix
vagrant snapshot pop
set ERRNO=!ERRORLEVEL!
popd
exit /b !ERRNO!
::--- END OF REVERT

::--- SAVE
:save
echo.Attemting to save current state of honeypot...
pushd %VM_DIR%
vagrant snapshot push
set ERRNO=!ERRORLEVEL!
popd
exit /b !ERRNO!
::--- END OF SAVE

::--- SSH
:ssh
if not exist %PUTTY_EXE_PATH% (
	echo.Path to Putty is incorrect. Fix path in script properties. Aborting...
	exit /b 1
)

start "" %PUTTY_EXE_PATH% localhost 2222
exit /b 0
::--- END OF SSH

::--- VM EXISTS
:_vm_exists
if exist %VAGRANT_METADATA_DIR% exit /b 0
exit /b 1
::--- END OF VM EXISTS

::--- MONITOR
:monitor
shift
if "%1"=="" (
	call :help_monitor
	exit /b 0
)

if not exist %VM_DIR% (
	echo.Honeypot must be configured first. Moving on...
	exit /b 1
)

echo %MONITORED_FOLDERS_FILE%

type NUL > %MONITORED_FOLDERS_FILE%

:_monitor_again
if not "%~1" == "" (
	echo.%~1 >> %MONITORED_FOLDERS_FILE%
	shift
	goto _monitor_again
)

pushd %VM_DIR%
vagrant provision --provision-with monitored_copy,monitor_copy,monitor_run
set ERRNO=!ERRORLEVEL!
popd
exit /b !ERRNO!
::--- END OF MONITOR

::--- HELP MONITOR
:help_monitor
echo.Monitor command establishes monitoring on given folders. 
echo.Usage of "monitor" command: 
echo.	%~n0 monitor /var/log/apache2 /var/log/mysql
exit /b 0
::--- END OF HELP MONITOR