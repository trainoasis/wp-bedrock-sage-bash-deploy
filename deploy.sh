#!/bin/bash
set -e 
set -o errexit

# NOTES
# 
# Use this script at your own risk. 
# MAKE SURE TO EDIT VARIABLES SECTION BEFORE RUNNING.
# 
# See PREREQUISITES and VARIABLES below for settings, but in general you can run the script like this:
# > sh deploy.sh --verbose"     

###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
# VARIABLES / CONSTANTS / FLAGS ###############################################################################################
###############################################################################################################################
###############################################################################################################################
###############################################################################################################################

#
# VARIABLES (local + git)
#
GIT_CLONE_URL="ssh://git@your_git_url:portif_needed/path/to/project.git"
LOCAL_TEMP_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )" # this is where our $LOCAL_TEMP_FOLDER_NAME is created (script directory)
THEME_FOLDER_PATH="web/app/themes/theme_name" # Bedrock path to our Sage theme
VERBOSE=false
BRANCH="master"

DOMAIN_ROOT_FOLDER_NAME="mypage.com" # the name of the folder on the SERVER you will deploy to
REMOTE_PATH="/home/user/www/mypage.com" # whole remote path on the SERVER you are deploying to, including the folder

# Generates our .zip folder that would be deployed, but doesnt deploy it. 
# Useful if you want to test with DEPLOY_EXISTING variable below later on (testing ssh commands for example)
GENERATE_ONLY_DONT_DEPLOY=false

# Deploys existing $LOCAL_TEMP_FOLDER_NAME.zip without cloning and building production assets, without running composer etc. (way faster)
# Useful when doing multiple deploys for the same project one after another or when testing the script
DEPLOY_EXISTING=false 

#
# VARIABLES (server)
#
SSH_SERVER="user@my.server.com"
SSH_PORT="5050"

#
# CONSTANTS ( Do NOT change !!! )
#
LOCAL_TEMP_FOLDER_NAME="DEPLOY_TEMP" 
LOCAL_TEMP_FOLDER_PATH="$LOCAL_TEMP_PATH/$LOCAL_TEMP_FOLDER_NAME"
LOCAL_TEMP_THEME_FOLDER_PATH="$LOCAL_TEMP_FOLDER_PATH/$THEME_FOLDER_PATH"

PRIMARY_TXT='\033[32m'
WARNING_TXT='\033[31m'
TXT_RESET='\033[m'

print_usage() {
    echo " "
    echo "options:"
    echo "-h, --help                            show brief help"
    echo "--verbose                             show more info (actual commands) when executing script" 
    echo "--generateonly                        do not deploy, but instead only generate the deploy folder/zip locally. If used with --deployexisting, --generateonly is used."                         
    echo "--deployexisting                      deploy existing .zip folder (way faster). Doesnt remove the .zip afterwards. Use --generateonly first. If used with --generateonly, --generateonly is used."        
    echo "--branch develop                      define a different branch (master is default)"                                  
    echo " "
    echo "EXAMPLE USE: sh deploy.sh --verbose"                      
    exit 0
}


###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
# CHECK PARAMS WHEN SCRIPT RUNS ###############################################################################################
###############################################################################################################################
###############################################################################################################################
###############################################################################################################################

while test $# -gt 0; do
  case "$1" in
    --verbose)
      shift 
      VERBOSE=true
      printf "$PRIMARY_TXT Verbose is ON $TXT_RESET: will show commands executed\n\n"
      ;;
    -h|--help)
      print_usage
      ;;
    --deployexisting)
      shift 
      DEPLOY_EXISTING=true
      ;;
    --generateonly)
      shift 
      GENERATE_ONLY_DONT_DEPLOY=true
      ;;
    *)
      break
      ;;
  esac
done

if [ "$GENERATE_ONLY_DONT_DEPLOY" == true ] ; then
    DEPLOY_EXISTING=false
fi

# ask for confirmation before starting the script, just to make sure parameters are correct
script_start_check() {
    echo "DEPLOY EXISTING: $DEPLOY_EXISTING"
    echo "GENERATE ONLY: $GENERATE_ONLY_DONT_DEPLOY"
    echo " "
    if [ "$DEPLOY_EXISTING" != true ] ; then
        echo "$PRIMARY_TXT Cloning from: $TXT_RESET"
        printf ">>> $GIT_CLONE_URL"
        if [ -z ${BRANCH+x} ]; then
            :
        else
            printf " (branch: $BRANCH)"
        fi
        printf "\n$PRIMARY_TXT to: $TXT_RESET\n"
    fi
    echo ">>> $LOCAL_TEMP_FOLDER_PATH"
    echo " -  -  -  -  -  - "
    echo "$PRIMARY_TXT deploying to: $TXT_RESET"
    echo ">>> $SSH_SERVER:$SSH_PORT"
    echo ">>> $REMOTE_PATH"
    echo " "

    if [ "$GENERATE_ONLY_DONT_DEPLOY" == true ] ; then
        echo "Continue and $PRIMARY_TXT >> ONLY GENERATE << folder locally.$TXT_RESET $WARNING_TXT Will not deploy.$TXT_RESET"
    elif [ "$DEPLOY_EXISTING" == true ] ; then
        echo "Continue and $PRIMARY_TXT >> deploy EXISTING folder << $TXT_RESET to $PRIMARY_TXT >>'$REMOTE_PATH'<< $TXT_RESET. (fastest, keeps the .zip locally)"
    else
        echo "Continue and deploy to folder $PRIMARY_TXT >>'$REMOTE_PATH'<< $TXT_RESET. $WARNING_TXT Will do ALL THE STEPS (the longest)$TXT_RESET"
    fi

    read -p "Will create this path/folder if it does not exist yet! (yes/no)? " choice
    case "$choice" in 
      yes|YES|Yes ) 
        continue;;
      no|NO|No ) 
        echo "Please write yes / YES / Yes if you want to continue. Exiting."; exit 1 ;;
      * ) 
        echo "Please write yes / YES / Yes if you want to continue. Exiting."; exit 1 ;;
    esac
}

# check if DOMAIN_ROOT_FOLDER_NAME set, otherwise exit 
if [ -z ${DOMAIN_ROOT_FOLDER_NAME+x} ]
then 
    echo "$WARNING_TXT Missing flag $TXT_RESET: --deployfolder \n >> run script like so: sh deploy.sh"
    print_usage
    exit 1
fi

script_start_check

###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
# F U N C T I O N S ###########################################################################################################
###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
    
# print additional information based on --verbose flag
# use: print_if_verbose "commands, variables etc. here showing what commands we are firing for example"
print_if_verbose()
{
    if [ "$VERBOSE" = true ] ; then
        echo "   >>> $1"
    fi
}

# do git clone of our provided git url (remove folder before if exists)
git_clone_repo() 
{
    echo "$PRIMARY_TXT ===>>> cloning to our temp folder ... $TXT_RESET"
    print_if_verbose "git clone $GIT_CLONE_URL $LOCAL_TEMP_FOLDER_PATH"
    git clone $GIT_CLONE_URL $LOCAL_TEMP_FOLDER_PATH

    cd $LOCAL_TEMP_FOLDER_PATH

    if [ -z ${BRANCH+x} ]; then
        :
    else
        print_if_verbose "git checkout $BRANCH"
        git checkout $BRANCH
    fi

    printf "\n\n"
}

# remove stuff from repo that we do not want on our production
#  - WP themes that come inside bedrock wp folder, they just clutter our available space
#  - resources/assets in our theme (we are using /dist folder on production anyway!)
#  - node_modules in our theme
#  - cypress folder (e2e tests)
remove_non_production_stuff()
{
    echo "$PRIMARY_TXT ===>>> Removing non production folders & files $TXT_RESET"

    print_if_verbose "rm -rf web/wp/wp-content/themes/twenty*"
    cd $LOCAL_TEMP_FOLDER_PATH
    rm -rf web/wp/wp-content/themes/twenty*

    rm -rf .git .gitignore .env.example

    print_if_verbose "rm -rf $LOCAL_TEMP_THEME_FOLDER_PATH/resources/assets"
    cd $LOCAL_TEMP_THEME_FOLDER_PATH
    rm -rf resources/assets 

    # remove e2e tests 
    rm -rf cypress

    # acf-export*.json files (have them in GIT anyway)
    rm -f acf-export*.json

    print_if_verbose "rm -rf $LOCAL_TEMP_THEME_FOLDER_PATH/node_modules"
    rm -rf node_modules

    printf "\n\n"
}


# run composer install for Bedrock & Sage (root + theme)
run_composer()
{
    echo "$PRIMARY_TXT ===>>> running composer install in root and inside theme folder ... $TXT_RESET"
    print_if_verbose "cd $LOCAL_TEMP_FOLDER_PATH && composer install  --no-dev --quiet"
    composer install --no-dev --quiet
    cd $LOCAL_TEMP_THEME_FOLDER_PATH
    print_if_verbose "cd $LOCAL_TEMP_THEME_FOLDER_PATH && composer install --no-dev --quiet"
    composer install --no-dev --quiet
    printf "\n\n"
}

# build production assets
run_yarn()
{
    echo "$PRIMARY_TXT ===>>> building production assets locally in $LOCAL_TEMP_THEME_FOLDER_PATH ... $TXT_RESET"
    cd $LOCAL_TEMP_THEME_FOLDER_PATH
    print_if_verbose "cd $LOCAL_TEMP_THEME_FOLDER_PATH && yarn --silent"
    yarn --silent
    print_if_verbose "yarn build:production"
    yarn build:production 
    printf "\n\n"
}

# zip the contents of our temporary folder with the same name
zip_temp_folder()
{ 
    echo "$PRIMARY_TXT ===>>> Zipping our temporary folder ... $TXT_RESET"
    cd $LOCAL_TEMP_PATH
    print_if_verbose "cd $LOCAL_TEMP_PATH && zip -q -r $LOCAL_TEMP_FOLDER_NAME.zip $LOCAL_TEMP_FOLDER_NAME"
    zip -q -r $LOCAL_TEMP_FOLDER_NAME.zip $LOCAL_TEMP_FOLDER_NAME
    printf "\n\n"
}

# SCP our zipped folder to server
scp_temp_folder_to_server()
{
    echo "$PRIMARY_TXT ===>>> transfer our temporary folder to the server (ssh to create the folder FIRST - if not existing) ... $TXT_RESET"
    print_if_verbose "ssh $SSH_SERVER -p $SSH_PORT mkdir -p $REMOTE_PATH"
    print_if_verbose "scp -P $SSH_PORT $LOCAL_TEMP_FOLDER_NAME.zip $SSH_SERVER:$REMOTE_PATH"
    ssh $SSH_SERVER -p $SSH_PORT "mkdir -p $REMOTE_PATH"
    cd $LOCAL_TEMP_PATH
    scp -P $SSH_PORT $LOCAL_TEMP_FOLDER_NAME.zip $SSH_SERVER:$REMOTE_PATH # -q -o LogLevel=QUIET 
    printf "\n\n"
}

print_verbose_ssh_commands()
{
    print_if_verbose "set +e && ssh $SSH_SERVER -p $SSH_PORT <<EOL
        set -e

        cd $REMOTE_PATH 

        # move our zip to /www folder
        mv $LOCAL_TEMP_FOLDER_NAME.zip ../

        # move to www
        cd ..

        echo 'Zipping our whole domain folder $DOMAIN_ROOT_FOLDER_NAME may take some time based on folder size ... Please be patient'

        # zip our whole domain folder (backup)
        zip -q -r $DOMAIN_ROOT_FOLDER_NAME.zip $DOMAIN_ROOT_FOLDER_NAME

        # unzip our new deploy folder
        unzip -q -o $LOCAL_TEMP_FOLDER_NAME

        # then copy all the missing contents to our domain folder (uploads, languages, .env)
        if [ -f $REMOTE_PATH/.env ]; then
            cp $REMOTE_PATH/.env $LOCAL_TEMP_FOLDER_NAME/ && echo 'Copied .env'
        fi

        if [ -f $REMOTE_PATH/web/.htaccess ]; then
            cp $REMOTE_PATH/web/.htaccess $LOCAL_TEMP_FOLDER_NAME/web && echo 'Copied .htaccess'
        fi

        if [ -d $REMOTE_PATH/web/app/uploads ]; then
            cp -r $REMOTE_PATH/web/app/uploads/* $LOCAL_TEMP_FOLDER_NAME/web/app/uploads/ && echo 'Copied uploads folder'

            # remove composer cache so our Blade templates are updated
            rm -rf $LOCAL_TEMP_FOLDER_NAME/web/app/uploads/cache && echo 'Removed uploads/cache folder'
        fi

        if [ -d $REMOTE_PATH/$THEME_FOLDER_PATH/resources/languages ]; then
            cp -r $REMOTE_PATH/$THEME_FOLDER_PATH/resources/languages/* $LOCAL_TEMP_FOLDER_NAME/$THEME_FOLDER_PATH/resources/languages/ && echo 'Copied languages folder'
        fi

        # copy over plugins/* but DO NOT overwrite existing (-n)
        # (composer dependencies take precedence, but keep specific plugins for the domain too)
        if [ -d $REMOTE_PATH/web/app/plugins ]; then
            cp -Rn $REMOTE_PATH/web/app/plugins/* $LOCAL_TEMP_FOLDER_NAME/web/app/plugins/ && echo 'Copied over /plugins (the ones not a composer dependency)' || true
        fi

        # copy over WPML translations and other project specific languages (.mo files generated!)
        # (web/app/languages/wpml). WPML uses .mo files from v4.3.0 onwards
        # and OVERWRITE existing (no -n)
        if [ -d $REMOTE_PATH/web/app/languages ]; then
            cp -R $REMOTE_PATH/web/app/languages/* $LOCAL_TEMP_FOLDER_NAME/web/app/languages/ && echo 'Copied over /languages (mainly wpml .mo files!)' || true
        fi

        # remove our deploy folder zip
        rm -rf $LOCAL_TEMP_FOLDER_NAME.zip

        # go back to our project root and activate maintenance mode, then go back to www
        cd $REMOTE_PATH 
        wp maintenance-mode activate || true
        cd ..

        ############################################################
        # FROM HERE ON THE PAGE MIGHT NOT BE AVAILABLE FOR A WHILE
        ############################################################

        # rename current page www folder (faster than RM)
        mv ${DOMAIN_ROOT_FOLDER_NAME} ${DOMAIN_ROOT_FOLDER_NAME}_BEFORE_DEPLOY

        # rename our deploy folder to domain www folder name
        mv $LOCAL_TEMP_FOLDER_NAME $DOMAIN_ROOT_FOLDER_NAME

        # check for .env file existence
        if [ -f $REMOTE_PATH/.env ]
        then
            # activate our theme & plugins
            cd $DOMAIN_ROOT_FOLDER_NAME

            # (allow commands to fail, continue regardless)
            wp theme activate theme_name/resources || true
            #wp plugin activate --all || true # you might have to manually enable some plugins for them to work at this point

            # assign menus (allow commands to fail, continue regardless)
            wp menu location assign main-menu primary_navigation || true

            # set permalinks to Post name and flush them 
            # (flushes rules after automatically same as if you called wp rewrite flush which ruines our rewrite rules in non-default languages on category term pages
            #wp rewrite structure '/%postname%/' || true 
        else
            printf '\n\n>>> .env file missing! Make sure you create one inside $REMOTE_PATH <<<'
        fi

        rm -rf ${REMOTE_PATH}_BEFORE_DEPLOY

        # deactivate WP maintenance mode
        wp maintenance-mode deactivate || true
        # Throws 'Error: Maintenance mode already deactivated.' which is weird

        exit 0
    EOL"
}

# connect to server via ssh & unzip our zip
# unzip -q -o (-q => quiet mode, -o => overwrite without prompting, -d => folder where to extract)
ssh_to_server_and_do_stuff()
{
    echo "$PRIMARY_TXT ===>>> SSH to $SSH_SERVER -p $SSH_PORT (unzip etc.) $TXT_RESET"
    print_verbose_ssh_commands

    set +e
    #ssh  $SSH_SERVER -p $SSH_PORT "$(commands_on_server)"
    ssh $SSH_SERVER -p $SSH_PORT <<EOL
        set -e
        cd $REMOTE_PATH

        # move our zip to /www folder
        mv $LOCAL_TEMP_FOLDER_NAME.zip ../

        # move to www
        cd ..

        echo "Zipping our whole domain folder $DOMAIN_ROOT_FOLDER_NAME may take some time based on folder size ... Please be patient"

        # zip our whole domain folder (backup)
        zip -q -r $DOMAIN_ROOT_FOLDER_NAME.zip $DOMAIN_ROOT_FOLDER_NAME

        # unzip our new deploy folder
        unzip -q -o $LOCAL_TEMP_FOLDER_NAME

        # then copy all the missing contents to our domain folder (uploads, languages, .env)
        if [ -f $REMOTE_PATH/.env ]; then
            cp $REMOTE_PATH/.env $LOCAL_TEMP_FOLDER_NAME/ && echo 'Copied .env'
        fi

        if [ -f $REMOTE_PATH/web/.htaccess ]; then
            cp $REMOTE_PATH/web/.htaccess $LOCAL_TEMP_FOLDER_NAME/web && echo 'Copied .htaccess'
        fi

        if [ -d $REMOTE_PATH/web/app/uploads ]; then
            cp -r $REMOTE_PATH/web/app/uploads/* $LOCAL_TEMP_FOLDER_NAME/web/app/uploads/ && echo 'Copied uploads folder'

            # remove composer cache so our Blade templates are updated
            rm -rf $LOCAL_TEMP_FOLDER_NAME/web/app/uploads/cache && echo 'Removed uploads/cache folder'
        fi

        if [ -d $REMOTE_PATH/$THEME_FOLDER_PATH/resources/languages ]; then
            cp -r $REMOTE_PATH/$THEME_FOLDER_PATH/resources/languages/* $LOCAL_TEMP_FOLDER_NAME/$THEME_FOLDER_PATH/resources/languages/ && echo 'Copied languages folder'
        fi

        # copy over plugins/* but DO NOT overwrite existing (-n)
        # (composer dependencies take precedence, but keep specific plugins for the domain too)
        if [ -d $REMOTE_PATH/web/app/plugins ]; then
            cp -Rn $REMOTE_PATH/web/app/plugins/* $LOCAL_TEMP_FOLDER_NAME/web/app/plugins/ && echo 'Copied over /plugins (the ones not a composer dependency)' || true
        fi

        # copy over WPML translations and other project specific languages (.mo files generated!)
        # (web/app/languages/wpml). WPML uses .mo files from v4.3.0 onwards
        # and OVERWRITE existing (no -n)
        if [ -d $REMOTE_PATH/web/app/languages ]; then
            cp -R $REMOTE_PATH/web/app/languages/* $LOCAL_TEMP_FOLDER_NAME/web/app/languages/ && echo 'Copied over /languages (mainly wpml .mo files!)' || 'DID NOT COPY OVER'
        fi

        # remove our deploy folder zip
        rm -rf $LOCAL_TEMP_FOLDER_NAME.zip

        # go back to our project root and activate maintenance mode, then go back to www
        cd $REMOTE_PATH 
        wp maintenance-mode activate || true
        cd ..

        ############################################################
        # FROM HERE ON THE PAGE MIGHT NOT BE AVAILABLE FOR A WHILE
        ############################################################

        # rename current page www folder (faster than RM)
        mv ${DOMAIN_ROOT_FOLDER_NAME} ${DOMAIN_ROOT_FOLDER_NAME}_BEFORE_DEPLOY

        # rename our deploy folder to domain www folder name
        mv $LOCAL_TEMP_FOLDER_NAME $DOMAIN_ROOT_FOLDER_NAME

        # check for .env file existence
        if [ -f $REMOTE_PATH/.env ]
        then
            # activate our theme & plugins
            cd $DOMAIN_ROOT_FOLDER_NAME

            # (allow commands to fail, continue regardless)
            #wp theme activate theme_name/resources || true
            #wp plugin activate --all || true

            # assign menus (allow commands to fail, continue regardless)
            wp menu location assign main-menu primary_navigation || true

            # set permalinks to Post name and flush them 
            # (flushes rules after automatically same as if you called wp rewrite flush which ruines our rewrite rules in non-default languages on category term pages
            #wp rewrite structure '/%postname%/' || true 
        else
            printf '\n\n>>> .env file missing! Make sure you create one inside $REMOTE_PATH <<<'
        fi

        rm -rf ${REMOTE_PATH}_BEFORE_DEPLOY

        # deactivate WP maintenance mode
        wp maintenance-mode deactivate || true

        exit 0
EOL

    if [ $? -ne 0 ]; then
        done_alert_ssh_error_and_exit
    fi

    set -e

    printf "\n\n"
}

done_alert_ssh_error_and_exit()
{
    remove_local_temp_files
    echo "######################################################"
    echo "$WARNING_TXT >>> D E P L O Y: premature exit from ssh (check ssh errors/warnings) <<< $TXT_RESET"
    echo "######################################################"
    exit 0
}

# clean our local temp files
# this should be run even if anything went wrong before this line (trap?)
remove_local_temp_files()
{
    echo "$PRIMARY_TXT ===>>> cleaning after ourselves ... $TXT_RESET"
    print_if_verbose "rm -rf $LOCAL_TEMP_FOLDER_PATH && rm -rf $LOCAL_TEMP_FOLDER_PATH.zip"
    printf "\n\n"
    rm -rf $LOCAL_TEMP_FOLDER_PATH
    rm -rf $LOCAL_TEMP_FOLDER_PATH.zip
}

done_alert()
{
    echo "######################################################"
    echo "$PRIMARY_TXT >>> D E P L O Y   D O N E  ($DOMAIN_ROOT_FOLDER_NAME) <<< $TXT_RESET"
    echo "Time when done: `date "+%Y-%m-%d %H:%M:%S"`"
    echo "######################################################"
}

done_alert_only_generate()
{
    echo "######################################################"
    echo "$PRIMARY_TXT >>> GENERATED deploy folder - DID NOT DEPLOY IT <<< $TXT_RESET"
    echo "Time when done: `date "+%Y-%m-%d %H:%M:%S"`"
    echo "######################################################"
}

display_message_deploying_existing()
{
    echo "######################################################"
    echo " >>> Deploying existing .zip folder <<< "
    echo "######################################################"
}

###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
# M A I N #####################################################################################################################
###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
TIMEFORMAT='It took %R seconds.'

time {

    if [ "$DEPLOY_EXISTING" == true ] ; then
        display_message_deploying_existing
    else 
        remove_local_temp_files

        git_clone_repo

        # takes quite a while (comment when testing)
        run_composer

        # takes quite a while (~20 seconds easily) (comment when testing)
        run_yarn

        remove_non_production_stuff

        zip_temp_folder
    fi

    if [ "$GENERATE_ONLY_DONT_DEPLOY" == true ] ; then
        done_alert_only_generate
    else 
        scp_temp_folder_to_server

        ssh_to_server_and_do_stuff

        #if [ "$DEPLOY_EXISTING" != true ] ; then
        #    remove_local_temp_files
        #fi

        done_alert
    fi
}
