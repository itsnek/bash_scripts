#!/usr/bin/env bash

########################
# Author: Nikos Siachamis
# Date: 04-04-2022
# Drupal 8-9 installer
###########################


# >>>>>>>> default variables >>>>>>>>>>
# set defaults
version="0.1.1"
script_name=$(basename "$0")
script_dir="$(pwd)"
drupal_dir="../www/"

phpversion=""
project_name=""
drupalv=""
ans=""
answer=""

cp sample.env .env
file="$(pwd)/.env"
settings_file="$(pwd)/www/drupal-v9/web/sites/default/settings.php"
#[[ -z file ]] && cp sample.env .env


# Exit codes
# ==========
# 0 no error
# 1 script interrupted
# 2 error description

# <<<<<<<< default variables <<<<<<<<<<


# >>>>>>>>>>>>>> argument >>>>>>>>>>>>>>>>>>>>>
usage() {
    cat <<EOF

Name: 
=====
Drupal Installer

Description: 
============
This script installs and deploys Drupal 8 and 9.

Requirement:
============
You must have git,php 7.4/8 and MariaDB installed.

Usage:
======
./$script_name [ -n | --name] [ -dv | --drupal_version ] [ -pv | --php_version ] [ -v | --version ] [ -h | --help ] 
    -v | --version   Script version.
    -h | --help      Show help.
    -n | --name      Enter the name of the project.
    -dv| --drupal_version    Enter the needed drupal version(8 or 9)
    -pv| --php_version    Enter the needed php version(recommended 74 or 8)


Examples:
=========
    # Install all components at once
    ./drupal-installer.sh

    # get help
    ./drupal-installer.sh -h

    # get version
    ./drupal-installer.sh -v

    # set name 
    ./drupal-installer.sh -n lamp

    # set drupal version
    ./drupal-installer.sh -dv 9

    # set php version
    ./drupal-installer.sh -pv 74

    # set both name and drupal version    
    ./drupal-installer.sh -n lamp -dv 9

    # set both name and php version    
    ./drupal-installer.sh -n lamp -pv 8

    # set both php and drupal version    
    ./drupal-installer.sh -pv 8 -dv 9

    # set all name, drupal and php version    
    ./drupal-installer.sh -n lamp -dv 9 -pv 74

EOF
    if [[ -n $1 ]]; then
        exit 2
    fi
}

while [[ $# > 0 ]]; do

    case "$1" in
    -n | --name)
        project_name=$2
        shift 2
        ;;
    -dv | --drupal_version)
        drupalv=$2
        shift 2
        ;;
    -pv | --php_version)
        phpversion=$2
        shift 2
        ;;
    -y | --yes)
        ans="Y"
        answer="Y"
        shift 1
        ;;
    -v | --version)
        echo "$version"
        exit 0
        ;;
    -h | --help | *)
        usage
        exit 0
        ;;

    esac

done

# <<<<<<<<<<<<<<<<< argument <<<<<<<<<<<<<<<<<<<<<<


#>>>>>>>>>>>>>>>>>> functions >>>>>>>>>>>>>>>>>>>>>

fn_confirm() {

    while [[ $ans != @("Y"|"N") ]]; do

        read -rp "Do you want to install Drupal? yes/y or no/n   " PANS

        ans=$(echo "$PANS" | cut -c 1-1 | tr "[:lower:]" "[:upper:]")

        if [ "$ans" = "N" ]; then
            echo "Installation canceled."
            exit 2
        elif [ "$ans" = "Y" ]; then
            echo "Installation initializing."
        fi
        
    done

}

get_attributes() {

    if [[ -z $project_name ]]; then
        read -rp "What is your project's name?   " pr_name
        project_name=$pr_name
    fi

    while [[ $drupalv != @(8|9) ]]; do
        read -rp "Which Drupal version you need, 8 or 9?   " drv
        drupalv=$(echo "$drv" | cut -c 1-1)
    done

    while [[ $phpversion != @(8|74) ]]; do
        read -rp "Which PHP version you need, 7.4 or 8?(for drupal 8, 74 is the maximum)   " phpv
        phpversion="$phpv"
        if [[ $phpversion -eq 8 && $drupalv -eq 8 ]]; then 
            echo "Not matching php and drupal version."
            exit 2
        fi
    done

}


set_db(){

    cd $(pwd)
    docker-compose up -d --build #--force-recreate --no-deps
    
    if [ $drupalv = 8 ]; then
        docker exec -t "${project_name}"-php"${phpversion}" bash -c "composer install --working-dir=/var/www/drupal-v8/ -n -q"
    elif [ $drupalv = 9 ]; then
        docker exec -t "${project_name}"-php"${phpversion}" bash -c "composer install --working-dir=/var/www/drupal-v9/ -n -q"
	    docker cp $(pwd)/data/drupal-database/drupal9_dark_plus.sql "${project_name}"-mariadb106:/home/drupal9_dark_plus.sql
    fi

    docker exec -t "${project_name}"-php"${phpversion}" bash -c "chown -R www-data /var/www/*"

    docker exec -t "${project_name}"-mariadb106 bash -c "echo "max_allowed_packet=512M" >> etc/mysql/my.cnf"
    # docker exec -it "${project_name}"-mariadb106 bash -c "mysql --user=root -ptiger -e \"SET @@GLOBAL.max_allowed_packet=536870912;\""
    if [[ $? != 0 ]]; then
        echo "Changing max allowed packet's size failed."
        exit 1
    else         
        echo "Max allowed packet's size changed successfully."
    fi

    if [ $drupalv = 9 ]; then

    	docker exec -t "${project_name}"-mariadb106 bash -c "mysql --user=root -ptiger -e \"CREATE DATABASE drupal9_dark_plus;\""
    	if [[ $? != 0 ]]; then
        
            echo "Database creation failed." 
            
            while [[ $answer != @("Y"|"N") ]]; do
            
	            read -rp "Do you want to overwrite the existing?(yes/y or no/n)    " conf
                answer=$(echo "$conf" | cut -c 1-1 | tr "[:lower:]" "[:upper:]")
	            if [[ $answer == "N" ]]; then
	                echo "Terminating..."
                    exit 1
    	        else 
	                echo "Database overwritten."
	            fi
                
            done

    	else         
            echo "Database created successfully."
    	fi

    	docker exec -t "${project_name}"-mariadb106 bash -c "mysql --user=root -ptiger drupal9_dark_plus < /home/drupal9_dark_plus.sql"
    	if [[ $? != 0 ]]; then
            echo "The loading of data failed."
            exit 1
    	else         
            echo "Data loaded successfully."
    	fi

    fi

}

clean_cache(){

    docker exec "${project_name}"-php"${phpversion}" bash -c "../drupal-v9/vendor/bin/drush cr"
    if [[ $? != 0 ]]; then
        echo "Cache cleaning failed."
        exit 1
    fi

}

# <<<<<<<<<<<<<<<<< functions <<<<<<<<<<<<<<<<<<<<<


# >>>>>>>>>>>>>> event functions >>>>>>>>>>>>>>>>>>

# Exit event handler
function on_exit() {
tput cnorm # Show cursor. You need this if animation is used.
# i.e. clean-up code here
exit 0 # Exit gracefully.
}

# CTRL+C event handler
function on_ctrl_c() {
echo # Set cursor to the next line of '^C'
tput cnorm # show cursor. You need this if animation is used.
    echo  "Terminated with Ctrl+C."
exit 1 # Don't remove. Use a number (1-255) for error code.
}

# <<<<<<<<<<<<<< event functions <<<<<<<<<<<<<<<<<<


# >>>>>>>>>>>>>>>>>>>> main >>>>>>>>>>>>>>>>>>>>>>>

# Register exit event handler.
trap on_exit EXIT
# Register CTRL+C event handler
trap on_ctrl_c SIGINT

#Confirm installation
fn_confirm 

#Script's info
#usage

#Get the needed attributes if they aren't passed when running the script.
get_attributes

#Pass the attributes to .env file
sed -i 's/_CUSTOM_PROJECT_NAME_/'$project_name'/' $file
sed -i 's/_CUSTOM_DRUPAL_VERSION_/'$drupalv'/' $file
sed -i 's/_CUSTOM_PHP_VERSION_/'$phpversion'/' $file
sed -i 's/_CUSTOM_HOST_NAME_/'$project_name-mariadb106'/' $settings_file

#Script's process
set_db
if [ $drupalv = 9 ]; then
    clean_cache
fi

#Restart the database's container to set the changes
echo "Restarting container to set changes"
docker restart "${project_name}"-mariadb106

echo "
Installation completed successfully. 
"

exit 0

# <<<<<<<<<<<<<<<<<<<< main <<<<<<<<<<<<<<<<<<<<<<<
