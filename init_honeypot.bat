@echo off

REM --- Parameters
set VM_DIR_NAME=vm
set VAGRANT_BOX=hashicorp/precise32
REM --- End of parameters

set ROOT_DIR=%~dp0
set ROOT_DIR=%ROOT_DIR:~0,-1%
set VM_DIR=%ROOT_DIR%\%VM_DIR_NAME%
set VAGRANT_FILE_PATH=%VM_DIR%\Vagrantfile
set VAGRANT_METADATA_DIR=%VM_DIR%\.vagrant
set VAGRANT_SNAPSHOTS_DIR=%VM_DIR%\snapshots

echo Creating directory for Honeypot virtual machine definition: %VM_DIR%
mkdir %VM_DIR%

::--- Check vagrant installed
WHERE vagrant >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
	echo Vagrant is not installed. 1>&2
	exit /b 1
)

::--- Check if VM was already created
if exist %VAGRANT_METADATA_DIR% (
	echo Honeypot is already created. To create new honeypot, run "delete_honeypot.bat" first.
	exit /b 2
)

::--- Create vagrant VM definition
(
	echo Vagrant.configure^(2^) do ^|config^|
	echo   config.vm.box = "hashicorp/precise32"
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
	echo   config.vm.provision "puppet" do ^|puppet^|
	echo     puppet.manifests_path = "manifests"
	echo     puppet.manifest_file = "default.pp"
	echo   end
	echo end
)>%VAGRANT_FILE_PATH%

echo Definition for Honeypot created

::-------------------------------------
::-- FUNCTIONS SECTION
::-------------------------------------
