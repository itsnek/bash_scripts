#!/usr/bin/env bash

########################
# Author: Nikos Siachamis
# Date: 08-11-2021
# Drupal 8-9 installer
###########################


# >>>>>>>> default variables >>>>>>>>>>
# set defaults
version="0.1.1"
script_name=$(basename "$0")
script_dir="$(pwd)"
laravel_dir="../www/"

phpversion=""
project_name=""
db_name=""
ans=""
answer=""

cp sample.env .env
cp ./www/.env.example ./www/.env
file="$(pwd)/.env"
file2="$(pwd)/www/.env"
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
This script install and deploy Drupal 8 and 9.

Requirement:
============
You must have git,php 7.4/8 and MariaDB installed.

Usage:
======
./$script_name [ -n path | --name path] [ -db | --database ] [ -u | --uninstall ] [ -v | --version ] [ -h | --help ] 
    -v | --version   	  Script version.
    -h | --help      	  Show help.
    -n | --name      	  Enter the name of the project.
   -db | --database    	  Enter the name of the database that is going to be created and used.
   -pv | --php_version    Enter the needed php version(recommended 74 or 8).


Examples:
=========
    # Install all components at once
    ./drupal-installer.sh

    # get help
    ./drupal-installer.sh -h

    # get version
    ./drupal-installer.sh -v

    # set project name 
    ./drupal-installer.sh -n lamp

    # set database name
    ./drupal-installer.sh -db laravelDB

    # get php version
    ./drupal-installer.sh -pv 74

    # get both project and database name    
    ./drupal-installer.sh -n lamp -db laravelDB

    # get both project name and php version    
    ./drupal-installer.sh -n lamp -pv 8

    # get both php version and database name    
    ./drupal-installer.sh -pv 8 -db laravelDB

    # get all name, drupal and php version    
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
    -pv | --php_version)
        phpversion=$2
        shift 2
        ;;
    -db | --database)
        db_name=$2
        shift 2
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

        read -rp "Do you want to install Laravel? yes/y or no/n   " PANS

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

    if [[ -z $db_name ]]; then
        read -rp "What is your database's name?   " db_n
        db_name=$db_n
    fi

    while [[ $phpversion != @(8|74) ]]; do
        read -rp "Which PHP version you need, 7.4 or 8?(for drupal 8, 74 is the maximum)   " phpv
        phpversion="$phpv"
    done

}


set_db(){

    cd $(pwd)
    docker-compose up -d --build #--force-recreate --no-deps
    docker exec -it "${project_name}"-php"${phpversion}" bash -c "composer install --working-dir=/var/www/html/"

    docker exec -it "${project_name}"-php"${phpversion}" bash -c "chown -R www-data /var/www/html/storage/*" \
    -c "chown -R www-data /var/www/html/public/*"

    docker exec -it "${project_name}"-mariadb106 bash -c "echo "max_allowed_packet=512M" >> etc/mysql/my.cnf"
    if [[ $? != 0 ]]; then
        echo "Changing max allowed packet's size failed."
        exit 1
    else         
        echo "Max allowed packet's size changed successfully."
    fi

    docker exec -it "${project_name}"-php"${phpversion}" bash -c "apt-get update && apt-get install npm -y" \
    -c "npm cache clean -f" \
    -c "npm install -g n" \
    -c "n stable" \
    -c "PATH="$PATH"" 
    if [[ $? != 0 ]]; then
        echo "npm installation failed."
        exit 1
    else         
        echo "npm installed successfully."
    fi

    docker exec -it "${project_name}"-php"${phpversion}" bash -c "composer require laravel/ui" \
    -c "php artisan ui bootstrap --auth" -c "npm install && chown -R 33:0 /root/.npm && npm run dev && npm run production"
    if [[ $? != 0 ]]; then
        echo "Enabling authentication failed."
        exit 1
    else         
        echo "Authentication enabled successfully."
    fi

    docker exec -it "${project_name}"-mariadb106 bash -c "mysql --user=root -p<password> -e \"CREATE DATABASE ${db_name};\"" 
    if [[ $? != 0 ]]; then
        echo "Database creation failed."
        exit 1
    else         
        echo "Database created successfully."
    fi
    
    docker exec -it "${project_name}"-php"${phpversion}" bash -c "php artisan config:cache" 
    if [[ $? != 0 ]]; then
        echo "Cleaning cache failed."
        exit 1
    else
        echo "Cache cleaned successfully."
    fi

    docker exec -it "${project_name}"-php"${phpversion}" bash -c "php artisan migrate"
    if [[ $? != 0 ]]; then
        echo "Migrating tables failed."
        exit 1
    else
        echo "Migrating tables completed successfully."
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
sed -i 's/_CUSTOM_PHP_VERSION_/'$phpversion'/' $file
sed -i 's/_CUSTOM_PROJECT_NAME_/'$project_name'/' $file2
sed -i 's/_CUSTOM_DATABASE_NAME_/'$db_name'/' $file2

#Script's process
set_db

#Restart the database's container to set the changes
echo "Restarting container to set changes"
docker restart "${project_name}"-mariadb106

echo "
Installation completed successfully. 
"

exit 0

# <<<<<<<<<<<<<<<<<<<< main <<<<<<<<<<<<<<<<<<<<<<<