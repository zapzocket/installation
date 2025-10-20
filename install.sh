#!/bin/bash

# Checking Root Access
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m[ERROR]\033[0m Please run this script as \033[1mroot\033[0m."
    exit 1
fi

# Check SSL certificate status and days remaining
check_ssl_status() {
    # First get domain from config file
    if [ -f "/var/www/html/zapzocketconfig/config.php" ]; then
        domain=$(grep '^\$domainhosts' "/var/www/html/zapzocketconfig/config.php" | cut -d"'" -f2 | cut -d'/' -f1)

        if [ -n "$domain" ] && [ -f "/etc/letsencrypt/live/$domain/cert.pem" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" | cut -d= -f2)
            current_date=$(date +%s)
            expiry_timestamp=$(date -d "$expiry_date" +%s)
            days_remaining=$(( ($expiry_timestamp - $current_date) / 86400 ))
            if [ $days_remaining -gt 0 ]; then
                echo -e "\033[32m✅ SSL Certificate: $days_remaining days remaining (Domain: $domain)\033[0m"
            else
                echo -e "\033[31m❌ SSL Certificate: Expired (Domain: $domain)\033[0m"
            fi
        else
            echo -e "\033[33m⚠️ SSL Certificate: Not found for domain $domain\033[0m"
        fi
    else
        echo -e "\033[33m⚠️ Cannot check SSL: Config file not found\033[0m"
    fi
}

# Check bot installation status
check_bot_status() {
    if [ -f "/var/www/html/zapzocketconfig/config.php" ]; then
        echo -e "\033[32m✅ Bot is installed\033[0m"
        check_ssl_status
    else
        echo -e "\033[31m❌ Bot is not installed\033[0m"
    fi
}

# Display Logo
function show_logo() {
    clear
    echo -e "\033[1;34m"
    echo "================================================================================="
    echo "  ______      _____   _____  ____   _____ _  ________ _______ "
    echo " |___  /     |  __ \ / ____|/ __ \ / ____| |/ /  ____|__   __|"
    echo "    / / __ _| |__) | (___ | |  | | |    | ' /| |__     | |   "
    echo "   / / / _\` |  ___/ \___ \| |  | | |    |  < |  __|    | |   "
    echo "  / /_| (_| | |     ____) | |__| | |____| . \| |____   | |   "
    echo " /_____\__,_|_|    |_____/ \____/ \_____|_|\_\______|  |_|   "
    echo "================================================================================="
    echo -e "\033[0m"
    echo ""
    echo -e "\033[1;36mVersion:\033[0m \033[33m1.0.0\033[0m"
    echo -e "\033[1;36mGitHub Repository:\033[0m \033[34mhttps://github.com/zapzocket/installation\033[0m"
    echo ""
    echo -e "\033[1;36mInstallation Status:\033[0m"
    check_bot_status
    echo ""
}

function verify_installation() {
    echo -e "\n\033[1;36m========================================\033[0m"
    echo -e "\033[1;36m   Installation Verification Report\033[0m"
    echo -e "\033[1;36m========================================\033[0m\n"
    
    local errors=0
    local warnings=0
    
    # Check Apache service
    echo -e "\033[33m[1/10] Checking Apache service...\033[0m"
    if systemctl is-active --quiet apache2; then
        echo -e "\033[32m  ✅ Apache is running\033[0m"
    else
        echo -e "\033[31m  ❌ Apache is not running\033[0m"
        ((errors++))
    fi
    
    # Check MySQL service
    echo -e "\n\033[33m[2/10] Checking MySQL service...\033[0m"
    if check_marzban_installed; then
        MYSQL_CONTAINER=$(docker ps -q --filter "name=mysql" --no-trunc)
        if [ -n "$MYSQL_CONTAINER" ]; then
            echo -e "\033[32m  ✅ MySQL container is running (Marzban mode)\033[0m"
        else
            echo -e "\033[31m  ❌ MySQL container not found\033[0m"
            ((errors++))
        fi
    else
        if systemctl is-active --quiet mysql; then
            echo -e "\033[32m  ✅ MySQL is running\033[0m"
        else
            echo -e "\033[31m  ❌ MySQL is not running\033[0m"
            ((errors++))
        fi
    fi
    
    # Check bot directory
    echo -e "\n\033[33m[3/10] Checking bot directory...\033[0m"
    if [ -d "/var/www/html/zapzocketconfig" ]; then
        echo -e "\033[32m  ✅ Bot directory exists\033[0m"
        file_count=$(find /var/www/html/zapzocketconfig -type f | wc -l)
        echo -e "\033[36m     Files found: $file_count\033[0m"
    else
        echo -e "\033[31m  ❌ Bot directory not found\033[0m"
        ((errors++))
    fi
    
    # Check config file
    echo -e "\n\033[33m[4/10] Checking configuration file...\033[0m"
    CONFIG_PATH="/var/www/html/zapzocketconfig/config.php"
    if [ -f "$CONFIG_PATH" ]; then
        echo -e "\033[32m  ✅ Config file exists\033[0m"
        
        # Check file permissions
        perms=$(stat -c "%a" "$CONFIG_PATH")
        if [ "$perms" = "755" ] || [ "$perms" = "644" ]; then
            echo -e "\033[32m  ✅ Config file permissions: $perms\033[0m"
        else
            echo -e "\033[33m  ⚠️  Config file permissions: $perms (expected 755 or 644)\033[0m"
            ((warnings++))
        fi
        
        # Verify config contents
        if grep -q '$APIKEY' "$CONFIG_PATH" && grep -q '$dbname' "$CONFIG_PATH"; then
            echo -e "\033[32m  ✅ Config file structure is valid\033[0m"
        else
            echo -e "\033[31m  ❌ Config file structure is invalid\033[0m"
            ((errors++))
        fi
    else
        echo -e "\033[31m  ❌ Config file not found\033[0m"
        ((errors++))
    fi
    
    # Check database connection
    echo -e "\n\033[33m[5/10] Checking database connection...\033[0m"
    if extract_db_credentials 2>/dev/null; then
        if check_marzban_installed; then
            MYSQL_CONTAINER=$(docker ps -q --filter "name=mysql" --no-trunc)
            if docker exec "$MYSQL_CONTAINER" mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
                echo -e "\033[32m  ✅ Database connection successful\033[0m"
                echo -e "\033[36m     Database: $DB_NAME\033[0m"
                echo -e "\033[36m     User: $DB_USER\033[0m"
            else
                echo -e "\033[31m  ❌ Database connection failed\033[0m"
                ((errors++))
            fi
        else
            if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
                echo -e "\033[32m  ✅ Database connection successful\033[0m"
                echo -e "\033[36m     Database: $DB_NAME\033[0m"
                echo -e "\033[36m     User: $DB_USER\033[0m"
                
                # Check table count
                table_count=$(mysql -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
                if [ "$table_count" -gt 1 ]; then
                    echo -e "\033[32m  ✅ Database tables: $((table_count - 1))\033[0m"
                else
                    echo -e "\033[33m  ⚠️  No tables found in database\033[0m"
                    ((warnings++))
                fi
            else
                echo -e "\033[31m  ❌ Database connection failed\033[0m"
                ((errors++))
            fi
        fi
    else
        echo -e "\033[33m  ⚠️  Could not extract database credentials\033[0m"
        ((warnings++))
    fi
    
    # Check PHP extensions
    echo -e "\n\033[33m[6/10] Checking PHP extensions...\033[0m"
    required_extensions=("mysqli" "curl" "json" "mbstring" "zip")
    missing_extensions=()
    
    for ext in "${required_extensions[@]}"; do
        if php -m 2>/dev/null | grep -q "^$ext$"; then
            echo -e "\033[32m  ✅ $ext\033[0m"
        else
            echo -e "\033[31m  ❌ $ext (missing)\033[0m"
            missing_extensions+=("$ext")
            ((errors++))
        fi
    done
    
    # Check SSL certificate
    echo -e "\n\033[33m[7/10] Checking SSL certificate...\033[0m"
    if [ -f "$CONFIG_PATH" ]; then
        domain=$(grep '^\$domainhosts' "$CONFIG_PATH" | cut -d"'" -f2 | cut -d'/' -f1)
        
        if [ -n "$domain" ] && [ -f "/etc/letsencrypt/live/$domain/cert.pem" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" | cut -d= -f2)
            current_date=$(date +%s)
            expiry_timestamp=$(date -d "$expiry_date" +%s)
            days_remaining=$(( ($expiry_timestamp - $current_date) / 86400 ))
            
            if [ $days_remaining -gt 30 ]; then
                echo -e "\033[32m  ✅ SSL certificate valid for $days_remaining days\033[0m"
                echo -e "\033[36m     Domain: $domain\033[0m"
            elif [ $days_remaining -gt 0 ]; then
                echo -e "\033[33m  ⚠️  SSL certificate expires in $days_remaining days\033[0m"
                echo -e "\033[36m     Domain: $domain\033[0m"
                ((warnings++))
            else
                echo -e "\033[31m  ❌ SSL certificate expired\033[0m"
                ((errors++))
            fi
        else
            echo -e "\033[33m  ⚠️  SSL certificate not found (domain: ${domain:-unknown})\033[0m"
            ((warnings++))
        fi
    else
        echo -e "\033[33m  ⚠️  Cannot check SSL (config not found)\033[0m"
        ((warnings++))
    fi
    
    # Check webhook
    echo -e "\n\033[33m[8/10] Checking Telegram webhook...\033[0m"
    if [ -f "$CONFIG_PATH" ]; then
        BOT_TOKEN=$(grep '^\$APIKEY' "$CONFIG_PATH" | awk -F"'" '{print $2}')
        
        if [ -n "$BOT_TOKEN" ]; then
            webhook_info=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo")
            webhook_url=$(echo "$webhook_info" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
            
            if [ -n "$webhook_url" ]; then
                echo -e "\033[32m  ✅ Webhook is configured\033[0m"
                echo -e "\033[36m     URL: $webhook_url\033[0m"
            else
                echo -e "\033[31m  ❌ Webhook not configured\033[0m"
                ((errors++))
            fi
        else
            echo -e "\033[33m  ⚠️  Bot token not found in config\033[0m"
            ((warnings++))
        fi
    else
        echo -e "\033[33m  ⚠️  Cannot check webhook (config not found)\033[0m"
        ((warnings++))
    fi
    
    # Check file ownership
    echo -e "\n\033[33m[9/10] Checking file ownership...\033[0m"
    if [ -d "/var/www/html/zapzocketconfig" ]; then
        owner=$(stat -c "%U:%G" "/var/www/html/zapzocketconfig")
        if [ "$owner" = "www-data:www-data" ]; then
            echo -e "\033[32m  ✅ Correct ownership: $owner\033[0m"
        else
            echo -e "\033[33m  ⚠️  Ownership: $owner (expected www-data:www-data)\033[0m"
            ((warnings++))
        fi
    fi
    
    # Check disk space
    echo -e "\n\033[33m[10/10] Checking disk space...\033[0m"
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 80 ]; then
        echo -e "\033[32m  ✅ Disk usage: ${disk_usage}%\033[0m"
    elif [ "$disk_usage" -lt 90 ]; then
        echo -e "\033[33m  ⚠️  Disk usage: ${disk_usage}% (getting high)\033[0m"
        ((warnings++))
    else
        echo -e "\033[31m  ❌ Disk usage: ${disk_usage}% (critically high)\033[0m"
        ((errors++))
    fi
    
    # Summary
    echo -e "\n\033[1;36m========================================\033[0m"
    echo -e "\033[1;36m           Verification Summary\033[0m"
    echo -e "\033[1;36m========================================\033[0m"
    
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        echo -e "\n\033[1;32m✅ Perfect! All checks passed successfully.\033[0m"
        echo -e "\033[32mYour ZapSocket Bot installation is fully operational.\033[0m\n"
    elif [ $errors -eq 0 ]; then
        echo -e "\n\033[1;33m⚠️  Installation completed with $warnings warning(s).\033[0m"
        echo -e "\033[33mYour bot should work, but consider addressing the warnings.\033[0m\n"
    else
        echo -e "\n\033[1;31m❌ Installation has $errors error(s) and $warnings warning(s).\033[0m"
        echo -e "\033[31mPlease fix the errors before using the bot.\033[0m\n"
    fi
    
    read -p "Press Enter to continue..."
}

# Display Menu
function show_menu() {
    show_logo
    echo -e "\033[1;36m1)\033[0m Install ZapSocket Bot"
    echo -e "\033[1;36m2)\033[0m Update ZapSocket Bot"
    echo -e "\033[1;36m3)\033[0m Remove ZapSocket Bot"
    echo -e "\033[1;36m4)\033[0m Export Database"
    echo -e "\033[1;36m5)\033[0m Import Database"
    echo -e "\033[1;36m6)\033[0m Configure Automated Backup"
    echo -e "\033[1;36m7)\033[0m Renew SSL Certificates"
    echo -e "\033[1;36m8)\033[0m Change Domain"
    echo -e "\033[1;36m9)\033[0m Additional Bot Management"
    echo -e "\033[1;36m10)\033[0m Verify Installation" # Added verification option to menu
    echo -e "\033[1;36m11)\033[0m Exit" # Updated exit number
    echo ""
    read -p "Select an option [1-11]: " option
    case $option in
        1) install_bot ;;
        2) update_bot ;;
        3) remove_bot ;;
        4) export_database ;;
        5) import_database ;;
        6) auto_backup ;;
        7) renew_ssl ;;
        8) change_domain ;;
        9) manage_additional_bots ;;
        10) verify_installation ;; # Added verification call
        11)
            echo -e "\033[32mExiting...\033[0m"
            exit 0
            ;;
        *)
            echo -e "\033[31mInvalid option. Please try again.\033[0m"
            show_menu
            ;;
    esac
}

function check_marzban_installed() {
    if [ -f "/opt/marzban/docker-compose.yml" ]; then
        return 0  # Marzban installed
    else
        return 1  # Marzban not installed
    fi
}

# Detect database type for Marzban
function detect_database_type() {
    COMPOSE_FILE="/opt/marzban/docker-compose.yml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo "unknown"
        return 1
    fi
    if grep -q "^[[:space:]]*mysql:" "$COMPOSE_FILE"; then
        echo "mysql"
        return 0
    elif grep -q "^[[:space:]]*mariadb:" "$COMPOSE_FILE"; then
        echo "mariadb"
        return 1
    else
        echo "sqlite"
        return 1
    fi
}

# Find a free port between 3300 and 3330
function find_free_port() {
    for port in {3300..3330}; do
        if ! ss -tuln | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    echo -e "\033[31m[ERROR] No free port found between 3300 and 3330.\033[0m"
    exit 1
}

# Function to fix update issues by changing mirrors
function fix_update_issues() {
    echo -e "\e[33mTrying to fix update issues by changing mirrors...\033[0m"

    cp /etc/apt/sources.list /etc/apt/sources.list.backup

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | cut -d '"' -f2)
        UBUNTU_CODENAME=$(cat /etc/os-release | grep UBUNTU_CODENAME | cut -d '=' -f2)
    else
        echo -e "\e[91mCould not detect Ubuntu version.\033[0m"
        return 1
    fi

    MIRRORS=(
        "archive.ubuntu.com"
        "us.archive.ubuntu.com"
        "fr.archive.ubuntu.com"
        "de.archive.ubuntu.com"
        "mirrors.digitalocean.com"
        "mirrors.linode.com"
    )

    for mirror in "${MIRRORS[@]}"; do
        echo -e "\e[33mTrying mirror: $mirror\033[0m"
        cat > /etc/apt/sources.list << EOF
deb http://$mirror/ubuntu/ $UBUNTU_CODENAME main restricted universe multiverse
deb http://$mirror/ubuntu/ $UBUNTU_CODENAME-updates main restricted universe multiverse
deb http://$mirror/ubuntu/ $UBUNTU_CODENAME-security main restricted universe multiverse
EOF

        if apt-get update 2>/dev/null; then
            echo -e "\e[32mSuccessfully updated using mirror: $mirror\033[0m"
            return 0
        fi
    done

    mv /etc/apt/sources.list.backup /etc/apt/sources.list
    echo -e "\e[91mAll mirrors failed. Restored original sources.list\033[0m"
    return 1
}

# Install Function
function install_bot() {
    echo -e "\e[32mInstalling ZapSocket Bot... \033[0m\n"

    if check_marzban_installed; then
        echo -e "\033[41m[IMPORTANT WARNING]\033[0m \033[1;33mMarzban detected. Proceeding with Marzban-compatible installation.\033[0m"
        install_bot_with_marzban "$@"
        return 0
    fi

    add_php_ppa() {
        sudo add-apt-repository -y ppa:ondrej/php || {
            echo -e "\e[91mError: Failed to add PPA ondrej/php.\033[0m"
            return 1
        }
    }

    add_php_ppa_with_locale() {
        sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || {
            echo -e "\e[91mError: Failed to add PPA ondrej/php with locale override.\033[0m"
            return 1
        }
    }

    if ! add_php_ppa; then
        echo "Failed to add PPA with default locale, retrying with locale override..."
        if ! add_php_ppa_with_locale; then
            echo "Failed to add PPA even with locale override. Exiting..."
            exit 1
        fi
    fi

    if ! (sudo apt update && sudo apt upgrade -y); then
        echo -e "\e[93mUpdate/upgrade failed. Attempting to fix using alternative mirrors...\033[0m"
        if fix_update_issues; then
            if sudo apt update && sudo apt upgrade -y; then
                echo -e "\e[92mThe server was successfully updated after fixing mirrors...\033[0m\n"
            else
                echo -e "\e[91mError: Failed to update even after trying alternative mirrors.\033[0m"
                exit 1
            fi
        else
            echo -e "\e[91mError: Failed to update/upgrade packages and mirror fix failed.\033[0m"
            exit 1
        fi
    else
        echo -e "\e[92mThe server was successfully updated ...\033[0m\n"
    fi

    sudo apt-get install software-properties-common || {
        echo -e "\e[91mError: Failed to install software-properties-common.\033[0m"
        exit 1
    }

    sudo apt install -y git unzip curl || {
        echo -e "\e[91mError: Failed to install required packages.\033[0m"
        exit 1
    }

    DEBIAN_FRONTEND=noninteractive apt install -y php8.2 php8.2-fpm php8.2-mysql || {
        echo -e "\e[91mError: Failed to install PHP 8.2 and related packages.\033[0m"
        exit 1
    }

    PKG=(
        lamp-server^
        libapache2-mod-php
        mysql-server
        apache2
        php-mbstring
        php-zip
        php-gd
        php-json
        php-curl
    )

    for i in "${PKG[@]}"; do
        dpkg -s $i &>/dev/null
        if [ $? -eq 0 ]; then
            echo "$i is already installed"
        else
            if ! DEBIAN_FRONTEND=noninteractive sudo apt install -y $i; then
                echo -e "\e[91mError installing $i. Exiting...\033[0m"
                exit 1
            fi
        fi
    done

    echo -e "\n\e[92mPackages Installed, Continuing ...\033[0m\n"

    echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | sudo debconf-set-selections
    echo 'phpmyadmin phpmyadmin/app-password-confirm password zapzocketpass' | sudo debconf-set-selections
    echo 'phpmyadmin phpmyadmin/mysql/admin-pass password zapzocketpass' | sudo debconf-set-selections
    echo 'phpmyadmin phpmyadmin/mysql/app-pass password zapzocketpass' | sudo debconf-set-selections
    echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | sudo debconf-set-selections

    sudo apt-get install phpmyadmin -y || {
        echo -e "\e[91mError: Failed to install phpMyAdmin.\033[0m"
        exit 1
    }

    if [ -f /etc/apache2/conf-available/phpmyadmin.conf ]; then
        sudo rm -f /etc/apache2/conf-available/phpmyadmin.conf && echo -e "\e[92mRemoved existing phpMyAdmin configuration.\033[0m"
    fi

    sudo ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf || {
        echo -e "\e[91mError: Failed to create symbolic link for phpMyAdmin configuration.\033[0m"
        exit 1
    }

    sudo a2enconf phpmyadmin.conf || {
        echo -e "\e[91mError: Failed to enable phpMyAdmin configuration.\033[0m"
        exit 1
    }
    sudo systemctl restart apache2 || {
        echo -e "\e[91mError: Failed to restart Apache2 service.\033[0m"
        exit 1
    }

    sudo apt-get install -y php-soap || {
        echo -e "\e[91mError: Failed to install php-soap.\033[0m"
        exit 1
    }

    sudo apt-get install libapache2-mod-php || {
        echo -e "\e[91mError: Failed to install libapache2-mod-php.\033[0m"
        exit 1
    }

    sudo systemctl enable mysql.service || {
        echo -e "\e[91mError: Failed to enable MySQL service.\033[0m"
        exit 1
    }
    sudo systemctl start mysql.service || {
        echo -e "\e[91mError: Failed to start MySQL service.\033[0m"
        exit 1
    }
    sudo systemctl enable apache2 || {
        echo -e "\e[91mError: Failed to enable Apache2 service.\033[0m"
        exit 1
    }
    sudo systemctl start apache2 || {
        echo -e "\e[91mError: Failed to start Apache2 service after UFW update.\033[0m"
        exit 1
    }

    sudo apt-get install ufw -y || {
        echo -e "\e[91mError: Failed to install UFW.\033[0m"
        exit 1
    }
    ufw allow 'Apache' || {
        echo -e "\e[91mError: Failed to allow Apache in UFW.\033[0m"
        exit 1
    }
    sudo systemctl restart apache2 || {
        echo -e "\e[91mError: Failed to restart Apache2 service after UFW update.\033[0m"
        exit 1
    }

    sudo apt-get install -y git || {
        echo -e "\e[91mError: Failed to install Git.\033[0m"
        exit 1
    }
    sudo apt-get install -y wget || {
        echo -e "\e[91mError: Failed to install Wget.\033[0m"
        exit 1
    }
    sudo apt-get install -y unzip || {
        echo -e "\e[91mError: Failed to install Unzip.\033[0m"
        exit 1
    }
    sudo apt install curl -y || {
        echo -e "\e[91mError: Failed to install cURL.\033[0m"
        exit 1
    }
    sudo apt-get install -y php-ssh2 || {
        echo -e "\e[91mError: Failed to install php-ssh2.\033[0m"
        exit 1
    }
    sudo apt-get install -y libssh2-1-dev libssh2-1 || {
        echo -e "\e[91mError: Failed to install libssh2.\033[0m"
        exit 1
    }
    sudo apt install jq -y || {
        echo -e "\e[91mError: Failed to install jq.\033[0m"
        exit 1
    }

    sudo systemctl restart apache2.service || {
        echo -e "\e[91mError: Failed to restart Apache2 service.\033[0m"
        exit 1
    }

    BOT_DIR="/var/www/html/zapzocketconfig"
    if [ -d "$BOT_DIR" ]; then
        echo -e "\e[93mDirectory $BOT_DIR already exists. Removing...\033[0m"
        sudo rm -rf "$BOT_DIR" || {
            echo -e "\e[91mError: Failed to remove existing directory $BOT_DIR.\033[0m"
            exit 1
        }
    fi

    sudo mkdir -p "$BOT_DIR"
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "\e[91mError: Failed to create directory $BOT_DIR.\033[0m"
        exit 1
    fi

    ZIP_URL="https://github.com/zapzocket/installation/archive/refs/heads/main.zip"

    # Check for version flag
    if [[ "$1" == "-v" && "$2" == "beta" ]] || [[ "$1" == "-beta" ]] || [[ "$1" == "-" && "$2" == "beta" ]]; then
        ZIP_URL="https://github.com/zapzocket/installation/archive/refs/heads/main.zip"
    elif [[ "$1" == "-v" && -n "$2" ]]; then
        ZIP_URL="https://github.com/zapzocket/installation/archive/refs/tags/$2.zip"
    fi

    TEMP_DIR="/tmp/zapzocket"
    mkdir -p "$TEMP_DIR"
    wget -O "$TEMP_DIR/bot.zip" "$ZIP_URL" || {
        echo -e "\e[91mError: Failed to download the specified version.\033[0m"
        exit 1
    }

    unzip "$TEMP_DIR/bot.zip" -d "$TEMP_DIR"
    EXTRACTED_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d)
    mv "$EXTRACTED_DIR"/* "$BOT_DIR" || {
        echo -e "\e[91mError: Failed to move extracted files.\033[0m"
        exit 1
    }
    rm -rf "$TEMP_DIR"

    sudo chown -R www-data:www-data "$BOT_DIR"
    sudo chmod -R 755 "$BOT_DIR"

    echo -e "\n\033[33mZapSocket config and script have been installed successfully.\033[0m"

    wait
    if [ ! -d "/root/confzapzocket" ]; then
        sudo mkdir /root/confzapzocket || {
            echo -e "\e[91mError: Failed to create /root/confzapzocket directory.\033[0m"
            exit 1
        }

        sleep 1

        touch /root/confzapzocket/dbrootzapzocket.txt || {
            echo -e "\e[91mError: Failed to create dbrootzapzocket.txt.\033[0m"
            exit 1
        }
        sudo chmod -R 777 /root/confzapzocket/dbrootzapzocket.txt || {
            echo -e "\e[91mError: Failed to set permissions for dbrootzapzocket.txt.\033[0m"
            exit 1
        }
        sleep 1

        randomdbpasstxt=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-8)

        ASAS="$"

        echo "${ASAS}user = 'root';" >> /root/confzapzocket/dbrootzapzocket.txt
        echo "${ASAS}pass = '${randomdbpasstxt}';" >> /root/confzapzocket/dbrootzapzocket.txt
        echo "${ASAS}path = '${RANDOM_NUMBER}';" >> /root/confzapzocket/dbrootzapzocket.txt

        sleep 1

        passs=$(cat /root/confzapzocket/dbrootzapzocket.txt | grep '$pass' | cut -d"'" -f2)
        userrr=$(cat /root/confzapzocket/dbrootzapzocket.txt | grep '$user' | cut -d"'" -f2)

        sudo mysql -u $userrr -p$passs -e "alter user '$userrr'@'localhost' identified with mysql_native_password by '$passs';FLUSH PRIVILEGES;" || {
            echo -e "\e[91mError: Failed to alter MySQL user. Attempting recovery...\033[0m"

            sudo sed -i '$ a skip-grant-tables' /etc/mysql/mysql.conf.d/mysqld.cnf
            sudo systemctl restart mysql

            sudo mysql <<EOF
DROP USER IF EXISTS 'root'@'localhost';
CREATE USER 'root'@'localhost' IDENTIFIED BY '${passs}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

            sudo sed -i '/skip-grant-tables/d' /etc/mysql/mysql.conf.d/mysqld.cnf
            sudo systemctl restart mysql
        }
    fi

    ROOT_PASSWORD=$(cat /root/confzapzocket/dbrootzapzocket.txt | grep '$pass' | cut -d"'" -f2)
    ROOT_USER=$(cat /root/confzapzocket/dbrootzapzocket.txt | grep '$user' | cut -d"'" -f2)

    if [ -n "$ROOT_PASSWORD" ] && [ -n "$ROOT_USER" ]; then
        randomdbdb=$(openssl rand -base64 10 | tr -dc 'a-zA-Z' | cut -c1-8)
        randomdbpass=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-12)

        if [[ $(mysql -u root -p$ROOT_PASSWORD -e "SHOW DATABASES LIKE 'zapzocket'") ]]; then
            clear
            echo -e "\n\e[91mYou have already created the database\033[0m\n"
        else
            dbname=zapzocket
            clear
            echo -e "\n\e[32mPlease enter the database username!\033[0m"
            printf "[+] Default user name is \e[91m${randomdbdb}\e[0m ( let it blank to use this user name ): "
            read dbuser
            if [ "$dbuser" = "" ]; then
                dbuser=$randomdbdb
            fi

            echo -e "\n\e[32mPlease enter the database password!\033[0m"
            printf "[+] Default password is \e[91m${randomdbpass}\e[0m ( let it blank to use this password ): "
            read -s dbpass
            if [ "$dbpass" = "" ]; then
                dbpass=$randomdbpass
            fi

            mysql -u root -p$ROOT_PASSWORD -e "CREATE DATABASE $dbname;" -e "CREATE USER '$dbuser'@'%' IDENTIFIED WITH mysql_native_password BY '$dbpass';GRANT ALL PRIVILEGES ON * . * TO '$dbuser'@'%';FLUSH PRIVILEGES;" -e "CREATE USER '$dbuser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$dbpass';GRANT ALL PRIVILEGES ON * . * TO '$dbuser'@'localhost';FLUSH PRIVILEGES;" || {
                echo -e "\e[91mError: Failed to create database or user.\033[0m"
                exit 1
            }

            echo -e "\n\e[95mDatabase Created.\033[0m"

            clear

            echo -e "\n\e[36mPlease enter your bot token:\033[0m"
            read YOUR_BOT_TOKEN

            echo -e "\n\e[36mPlease enter your domain (e.g., example.com):\033[0m"
            read YOUR_DOMAIN

            echo -e "\n\e[36mPlease enter your Telegram chat ID:\033[0m"
            read YOUR_CHAT_ID

            echo -e "\n\e[36mPlease enter your bot username (without @):\033[0m"
            read YOUR_BOTNAME

            echo -e "\n\e[33mInstalling SSL certificate for ${YOUR_DOMAIN}...\033[0m"
            
            # Install certbot if not already installed
            if ! command -v certbot &>/dev/null; then
                echo -e "\e[33mInstalling Certbot...\033[0m"
                sudo apt-get install -y certbot python3-certbot-apache || {
                    echo -e "\e[91mError: Failed to install Certbot.\033[0m"
                    exit 1
                }
            fi
            
            # Stop Apache temporarily for SSL setup
            sudo systemctl stop apache2
            
            # Get SSL certificate
            echo -e "\e[33mObtaining SSL certificate...\033[0m"
            if sudo certbot --apache --redirect --agree-tos --non-interactive --preferred-challenges http -d "$YOUR_DOMAIN"; then
                echo -e "\e[92mSSL certificate obtained successfully!\033[0m"
                SSL_INSTALLED=true
            else
                echo -e "\e[93mWarning: SSL certificate installation failed.\033[0m"
                SSL_INSTALLED=false
            fi
            
            # Start Apache
            sudo systemctl start apache2 || {
                echo -e "\e[91mError: Failed to start Apache2.\033[0m"
                exit 1
            }
            
            if [ "$SSL_INSTALLED" = true ]; then
                echo -e "\e[33mVerifying SSL certificate...\033[0m"
                sleep 3  # Wait for Apache to fully start
                
                # Test if HTTPS actually works
                if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${YOUR_DOMAIN}" | grep -q "200\|301\|302"; then
                    echo -e "\e[92mSSL certificate is working correctly!\033[0m"
                    SSL_WORKING=true
                else
                    echo -e "\e[93mWarning: SSL certificate exists but HTTPS connection failed.\033[0m"
                    echo -e "\e[93mThis may be due to DNS not being propagated yet.\033[0m"
                    echo -e "\e[93mFalling back to HTTP for webhook...\033[0m"
                    SSL_WORKING=false
                fi
            else
                SSL_WORKING=false
            fi

            ASAS="$"

            wait

            sleep 1

            file_path="/var/www/html/zapzocketconfig/config.php"

            if [ -f "$file_path" ]; then
              rm "$file_path" || {
                echo -e "\e[91mError: Failed to delete old config.php.\033[0m"
                exit 1
              }
              echo -e "File deleted successfully."
            else
              echo -e "File not found."
            fi

            sleep 1

            secrettoken=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-8)

            echo -e "<?php" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}APIKEY = '${YOUR_BOT_TOKEN}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}usernamedb = '${dbuser}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}passworddb = '${dbpass}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}dbname = '${dbname}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}domainhosts = '${YOUR_DOMAIN}/zapzocketconfig';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}adminnumber = '${YOUR_CHAT_ID}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}usernamebot = '${YOUR_BOTNAME}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}secrettoken = '${secrettoken}';" >> /var/www/html/zapzocketconfig/config.php
            echo -e "${ASAS}connect = mysqli_connect('localhost', \$usernamedb, \$passworddb, \$dbname);" >> /var/www/html/zapzocketconfig/config.php
            echo -e "if (${ASAS}connect->connect_error) {" >> /var/www/html/zapzocketconfig/config.php
            echo -e "die(' The connection to the database failed:' . ${ASAS}connect->connect_error);" >> /var/www/html/zapzocketconfig/config.php
            echo -e "}" >> /var/www/html/zapzocketconfig/config.php
            echo -e "mysqli_set_charset(${ASAS}connect, 'utf8mb4');" >> /var/www/html/zapzocketconfig/config.php
            text_to_save=$(cat <<EOF
\$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];
\$dsn = "mysql:host=localhost;dbname=${ASAS}dbname;charset=utf8mb4";
try {
     \$pdo = new PDO(\$dsn, \$usernamedb, \$passworddb, \$options);
} catch (\PDOException \$e) {
     throw new \PDOException(\$e->getMessage(), (int)\$e->getCode());
}
EOF
)
            echo -e "$text_to_save" >> /var/www/html/zapzocketconfig/config.php
            echo -e "?>" >> /var/www/html/zapzocketconfig/config.php

            sleep 1

            if [ "$SSL_WORKING" = true ]; then
                WEBHOOK_URL="https://${YOUR_DOMAIN}/zapzocketconfig/index.php"
                echo -e "\e[92mUsing HTTPS for webhook (SSL is working)\033[0m"
            else
                WEBHOOK_URL="http://${YOUR_DOMAIN}/zapzocketconfig/index.php"
                echo -e "\e[93mUsing HTTP for webhook (SSL not available or not working)\033[0m"
                echo -e "\e[93mNote: You can install/fix SSL later using option 7 from the menu.\033[0m"
            fi
            
            echo -e "\e[33mSetting webhook to: ${WEBHOOK_URL}\033[0m"
            
            WEBHOOK_RESPONSE=$(curl -s -F "url=${WEBHOOK_URL}" \
                 -F "secret_token=${secrettoken}" \
                 "https://api.telegram.org/bot${YOUR_BOT_TOKEN}/setWebhook")
            
            echo "$WEBHOOK_RESPONSE"
            
            if echo "$WEBHOOK_RESPONSE" | grep -q '"ok":true'; then
                echo -e "\e[92mWebhook set successfully!\033[0m"
            else
                echo -e "\e[91mWarning: Webhook setting may have failed. Response:\033[0m"
                echo "$WEBHOOK_RESPONSE"
            fi
            
            MESSAGE="✅ The bot is installed! for start the bot send /start command."
            curl -s -X POST "https://api.telegram.org/bot${YOUR_BOT_TOKEN}/sendMessage" -d chat_id="${YOUR_CHAT_ID}" -d text="$MESSAGE" || {
                echo -e "\e[91mError: Failed to send message to Telegram.\033[0m"
                exit 1
            }

            sleep 1
            sudo systemctl start apache2 || {
                echo -e "\e[91mError: Failed to start Apache2.\033[0m"
                exit 1
            }
            
            echo -e "\n\e[33mSetting up database tables...\033[0m"
            
            if [ "$SSL_WORKING" = true ]; then
                table_url="https://${YOUR_DOMAIN}/zapzocketconfig/table.php"
            else
                table_url="http://${YOUR_DOMAIN}/zapzocketconfig/table.php"
            fi
            
            echo -e "\e[33mAttempting to create tables at: ${table_url}\033[0m"
            
            if curl -f -s -o /dev/null --max-time 15 "$table_url"; then
                echo -e "\e[92mDatabase tables created successfully!\033[0m"
            else
                echo -e "\e[93mWarning: Could not automatically create database tables.\033[0m"
                echo -e "\e[93mPlease visit ${table_url} in your browser to complete setup.\033[0m"
                echo -e "\e[93mThis may happen if your domain DNS is not yet propagated.\033[0m"
            fi

            clear

            echo " "

            echo -e "\e[102mDomain Bot: ${table_url%table.php}\033[0m"
            if [ "$SSL_WORKING" = true ]; then
                echo -e "\e[104mDatabase address: https://${YOUR_DOMAIN}/phpmyadmin\033[0m"
            else
                echo -e "\e[104mDatabase address: http://${YOUR_DOMAIN}/phpmyadmin\033[0m"
            fi
            echo -e "\e[33mDatabase name: \e[36m${dbname}\033[0m"
            echo -e "\e[33mDatabase username: \e[36m${dbuser}\033[0m"
            echo -e "\e[33mDatabase password: \e[36m${dbpass}\033[0m"
            echo " "
            echo -e "\e[33mWebhook URL: \e[36m${WEBHOOK_URL}\033[0m"
            echo " "
            echo -e "ZapSocket Bot PRO"
            
            chmod +x /root/install.sh
            ln -vs /root/install.sh /usr/local/bin/zapzocket
        fi
    elif [ "$ROOT_PASSWORD" = "" ] || [ "$ROOT_USER" = "" ]; then
        echo -e "\n\e[36mThe password is empty.\033[0m\n"
    fi

    echo -e "\n\e[92mZapSocket Bot installation completed successfully!\033[0m"
    echo -e "\e[36mYou can now configure your bot through the web interface.\033[0m"
    
    echo -e "\n\033[33mRunning installation verification...\033[0m"
    sleep 2
    verify_installation
}

# Update Function
function update_bot() {
    echo "Updating ZapSocket Bot..."

    if ! sudo apt update && sudo apt upgrade -y; then
        echo -e "\e[91mError updating the server. Exiting...\033[0m"
        exit 1
    fi
    echo -e "\e[92mServer packages updated successfully...\033[0m\n"

    BOT_DIR="/var/www/html/zapzocketconfig"
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "\e[91mError: ZapSocket Bot is not installed. Please install it first.\033[0m"
        exit 1
    fi

    if [[ "$1" == "-beta" ]] || [[ "$1" == "-v" && "$2" == "beta" ]]; then
        ZIP_URL="https://github.com/zapzocket/installation/archive/refs/heads/main.zip"
    else
        ZIP_URL="https://github.com/zapzocket/installation/archive/refs/heads/main.zip"
    fi

    TEMP_DIR="/tmp/zapzocket_update"
    mkdir -p "$TEMP_DIR"

    wget -O "$TEMP_DIR/bot.zip" "$ZIP_URL" || {
        echo -e "\e[91mError: Failed to download update package.\033[0m"
        exit 1
    }
    unzip "$TEMP_DIR/bot.zip" -d "$TEMP_DIR"

    EXTRACTED_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d)

    CONFIG_PATH="/var/www/html/zapzocketconfig/config.php"
    TEMP_CONFIG="/root/zapzocket_config_backup.php"
    if [ -f "$CONFIG_PATH" ]; then
        cp "$CONFIG_PATH" "$TEMP_CONFIG" || {
            echo -e "\e[91mConfig file backup failed!\033[0m"
            exit 1
        }
    fi

    sudo rm -rf /var/www/html/zapzocketconfig || {
        echo -e "\e[91mFailed to remove old bot files!\033[0m"
        exit 1
    }

    sudo mkdir -p /var/www/html/zapzocketconfig
    sudo mv "$EXTRACTED_DIR"/* /var/www/html/zapzocketconfig/ || {
        echo -e "\e[91mFile transfer failed!\033[0m"
        exit 1
    }

    if [ -f "$TEMP_CONFIG" ]; then
        sudo mv "$TEMP_CONFIG" "$CONFIG_PATH" || {
            echo -e "\e[91mConfig file restore failed!\033[0m"
            exit 1
        }
    fi

    if [ -f "/var/www/html/zapzocketconfig/install.sh" ]; then
        sudo cp /var/www/html/zapzocketconfig/install.sh /root/install.sh
        echo -e "\n\e[92mCopied latest install.sh to /root/install.sh.\033[0m"
    fi

    sudo chown -R www-data:www-data /var/www/html/zapzocketconfig/
    sudo chmod -R 755 /var/www/html/zapzocketconfig/

    URL=$(grep '\$domainhosts' "$CONFIG_PATH" | cut -d"'" -f2)
    curl -s "https://$URL/table.php" || {
        echo -e "\e[91mSetup script execution failed!\033[0m"
    }

    rm -rf "$TEMP_DIR"

    echo -e "\n\e[92mZapSocket Bot updated to latest version successfully!\033[0m"

    if [ -f "/root/install.sh" ]; then
        sudo chmod +x /root/install.sh
        sudo ln -vsf /root/install.sh /usr/local/bin/zapzocket
        echo -e "\e[92mEnsured /root/install.sh is executable and 'zapzocket' command is linked.\033[0m"
    fi
}

# Remove Function
function remove_bot() {
    echo -e "\e[33mStarting ZapSocket Bot removal process...\033[0m"
    LOG_FILE="/var/log/remove_bot.log"
    echo "Log file: $LOG_FILE" > "$LOG_FILE"

    BOT_DIR="/var/www/html/zapzocketconfig"
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "\033[31m[ERROR]\033[0m ZapSocket Bot is not installed (/var/www/html/zapzocketconfig not found)." | tee -a "$LOG_FILE"
        echo -e "\033[33mNothing to remove. Exiting...\033[0m" | tee -a "$LOG_FILE"
        sleep 2
        exit 1
    fi

    read -p "Are you sure you want to remove ZapSocket Bot and its dependencies? (y/n): " choice
    if [[ "$choice" != "y" ]]; then
        echo "Aborting..." | tee -a "$LOG_FILE"
        exit 0
    fi

    if check_marzban_installed; then
        echo -e "\033[41m[IMPORTANT NOTICE]\033[0m \033[33mMarzban detected. Proceeding with Marzban-compatible removal.\033[0m" | tee -a "$LOG_FILE"
        remove_bot_with_marzban
        return 0
    fi

    echo "Removing ZapSocket Bot..." | tee -a "$LOG_FILE"

    if [ -d "$BOT_DIR" ]; then
        sudo rm -rf "$BOT_DIR" && echo -e "\e[92mBot directory removed: $BOT_DIR\033[0m" | tee -a "$LOG_FILE" || {
            echo -e "\e[91mFailed to remove bot directory: $BOT_DIR. Exiting...\033[0m" | tee -a "$LOG_FILE"
            exit 1
        }
    fi

    CONFIG_PATH="/root/config.php"
    if [ -f "$CONFIG_PATH" ]; then
        sudo shred -u -n 5 "$CONFIG_PATH" && echo -e "\e[92mConfig file securely removed: $CONFIG_PATH\033[0m" | tee -a "$LOG_FILE"
    fi

    echo -e "\e[33mRemoving MySQL and database...\033[0m" | tee -a "$LOG_FILE"
    sudo systemctl stop mysql
    sudo systemctl disable mysql
    sudo systemctl daemon-reload

    sudo apt --fix-broken install -y

    sudo apt-get purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*
    sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql /var/log/mysql.* /usr/lib/mysql /usr/include/mysql /usr/share/mysql
    sudo rm /lib/systemd/system/mysql.service
    sudo rm /etc/init.d/mysql

    sudo dpkg --remove --force-remove-reinstreq mysql-server mysql-server-8.0

    sudo find /etc/systemd /lib/systemd /usr/lib/systemd -name "*mysql*" -exec rm -f {} \;

    sudo apt-get purge -y mysql-server mysql-server-8.0 mysql-client mysql-client-8.0
    sudo apt-get purge -y mysql-client-core-8.0 mysql-server-core-8.0 mysql-common php-mysql php8.2-mysql php8.3-mysql php-mariadb-mysql-kbs

    sudo apt-get autoremove --purge -y
    sudo apt-get clean
    sudo apt-get update

    echo -e "\e[92mMySQL has been completely removed.\033[0m" | tee -a "$LOG_FILE"

    echo -e "\e[33mRemoving PHPMyAdmin...\033[0m" | tee -a "$LOG_FILE"
    if dpkg -s phpmyadmin &>/dev/null; then
        sudo apt-get purge -y phpmyadmin && echo -e "\e[92mPHPMyAdmin removed.\033[0m" | tee -a "$LOG_FILE"
        sudo apt-get autoremove -y && sudo apt-get autoclean -y
    else
        echo -e "\e[93mPHPMyAdmin is not installed.\033[0m" | tee -a "$LOG_FILE"
    fi

    echo -e "\e[33mRemoving Apache...\033[0m" | tee -a "$LOG_FILE"
    sudo systemctl stop apache2
    sudo systemctl disable apache2
    sudo apt-get purge -y apache2 apache2-utils apache2-bin apache2-data libapache2-mod-php*
    sudo apt-get autoremove --purge -y
    sudo apt-get autoclean -y
    sudo rm -rf /etc/apache2 /var/www/html

    echo -e "\e[33mRemoving Apache and PHP configurations...\033[0m" | tee -a "$LOG_FILE"
    sudo a2disconf phpmyadmin.conf &>/dev/null
    sudo rm -f /etc/apache2/conf-available/phpmyadmin.conf

    echo -e "\e[33mRemoving additional packages...\033[0m" | tee -a "$LOG_FILE"
    sudo apt-get remove -y php-soap php-ssh2 libssh2-1-dev libssh2-1

    echo -e "\e[92mZapSocket Bot has been completely removed.\033[0m" | tee -a "$LOG_FILE"
}

# Extract database credentials
function extract_db_credentials() {
    CONFIG_PATH="/var/www/html/zapzocketconfig/config.php"
    
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "\033[31m[ERROR]\033[0m Config file not found at $CONFIG_PATH."
        return 1
    fi

    DB_NAME=$(grep '^\$dbname' "$CONFIG_PATH" | awk -F"'" '{print $2}')
    DB_USER=$(grep '^\$usernamedb' "$CONFIG_PATH" | awk -F"'" '{print $2}')
    DB_PASS=$(grep '^\$passworddb' "$CONFIG_PATH" | awk -F"'" '{print $2}')

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        echo -e "\033[31m[ERROR]\033[0m Failed to extract database credentials from $CONFIG_PATH."
        return 1
    fi

    return 0
}

# Export Database Function
function export_database() {
    echo -e "\033[33mChecking database configuration...\033[0m"

    if ! extract_db_credentials; then
        return 1
    fi

    if check_marzban_installed; then
        echo -e "\033[31m[ERROR]\033[0m Exporting database is not supported when Marzban is installed due to database being managed by Docker."
        return 1
    fi

    echo -e "\033[33mVerifying database existence...\033[0m"

    if ! mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
        echo -e "\033[31m[ERROR]\033[0m Database $DB_NAME does not exist or credentials are incorrect."
        return 1
    fi

    BACKUP_FILE="/root/${DB_NAME}_backup.sql"
    echo -e "\033[33mCreating backup at $BACKUP_FILE...\033[0m"

    if ! mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_FILE"; then
        echo -e "\033[31m[ERROR]\033[0m Failed to create database backup."
        return 1
    fi

    echo -e "\033[32mBackup successfully created at $BACKUP_FILE.\033[0m"
}

# Import Database Function
function import_database() {
    echo -e "\033[33mChecking database configuration...\033[0m"

    if ! extract_db_credentials; then
        return 1
    fi

    if check_marzban_installed; then
        echo -e "\033[31m[ERROR]\033[0m Importing database is not supported when Marzban is installed due to database being managed by Docker."
        return 1
    fi

    echo -e "\033[33mVerifying database existence...\033[0m"

    if ! mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
        echo -e "\033[31m[ERROR]\033[0m Database $DB_NAME does not exist or credentials are incorrect."
        return 1
    fi

    while true; do
        read -p "Enter the path to the backup file [default: /root/${DB_NAME}_backup.sql]: " BACKUP_FILE
        BACKUP_FILE=${BACKUP_FILE:-/root/${DB_NAME}_backup.sql}

        if [[ -f "$BACKUP_FILE" && "$BACKUP_FILE" =~ \.sql$ ]]; then
            break
        else
            echo -e "\033[31m[ERROR]\033[0m Invalid file path or format. Please provide a valid .sql file."
        fi
    done

    echo -e "\033[33mImporting backup from $BACKUP_FILE...\033[0m"

    if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE"; then
        echo -e "\033[31m[ERROR]\033[0m Failed to import database from backup file."
        return 1
    fi

    echo -e "\033[32mDatabase successfully imported from $BACKUP_FILE.\033[0m"
}

# Placeholder functions for remaining features
function auto_backup() {
    echo -e "\033[36mConfigure Automated Backup\033[0m"

    BOT_DIR="/var/www/html/zapzocketconfig"
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "\033[31m[ERROR]\033[0m ZapSocket Bot is not installed ($BOT_DIR not found)."
        echo -e "\033[33mExiting...\033[0m"
        sleep 2
        return 1
    fi

    if ! extract_db_credentials; then
        return 1
    fi

    CONFIG_PATH="/var/www/html/zapzocketconfig/config.php"
    TELEGRAM_TOKEN=$(grep '^\$APIKEY' "$CONFIG_PATH" | awk -F"'" '{print $2}')
    TELEGRAM_CHAT_ID=$(grep '^\$adminnumber' "$CONFIG_PATH" | awk -F"'" '{print $2}')

    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "\033[31m[ERROR]\033[0m Failed to extract Telegram credentials from config.\033[0m"
        return 1
    fi

    if check_marzban_installed; then
        echo -e "\033[41m[NOTICE]\033[0m \033[33mMarzban detected. Using Marzban-compatible backup.\033[0m"
        BACKUP_SCRIPT="/root/backup_zapzocket_marzban.sh"
        MYSQL_CONTAINER=$(docker ps -q --filter "name=mysql" --no-trunc)
        if [ -z "$MYSQL_CONTAINER" ]; then
            echo -e "\033[31m[ERROR]\033[0m No running MySQL container found for Marzban."
            return 1
        fi
        cat <<EOF > "$BACKUP_SCRIPT"
#!/bin/bash
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
BACKUP_FILE="/root/\${DB_NAME}_\$(date +\"%Y%m%d_%H%M%S\").sql"
docker exec $MYSQL_CONTAINER mysqldump -u "\$DB_USER" -p"\$DB_PASS" "\$DB_NAME" > "\$BACKUP_FILE"
if [ \$? -eq 0 ]; then
    curl -F document=@"\$BACKUP_FILE" "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" -F chat_id="$TELEGRAM_CHAT_ID"
    rm "\$BACKUP_FILE"
else
    echo -e "\033[31m[ERROR]\033[0m Failed to create Marzban database backup."
fi
EOF
    else
        echo -e "\033[33mUsing standard backup.\033[0m"
        BACKUP_SCRIPT="/root/zapzocket_backup.sh"
        if ! mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
            echo -e "\033[31m[ERROR]\033[0m Database $DB_NAME does not exist or credentials are incorrect."
            return 1
        fi
        cat <<EOF > "$BACKUP_SCRIPT"
#!/bin/bash
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
BACKUP_FILE="/root/\${DB_NAME}_\$(date +\"%Y%m%d_%H%M%S\").sql"
mysqldump -u "\$DB_USER" -p"\$DB_PASS" "\$DB_NAME" > "\$BACKUP_FILE"
if [ \$? -eq 0 ]; then
    curl -F document=@"\$BACKUP_FILE" "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" -F chat_id="$TELEGRAM_CHAT_ID"
    rm "\$BACKUP_FILE"
else
    echo -e "\033[31m[ERROR]\033[0m Failed to create database backup."
fi
EOF
    fi

    chmod +x "$BACKUP_SCRIPT"

    CURRENT_CRON=$(crontab -l 2>/dev/null | grep "$BACKUP_SCRIPT" | grep -v "^#")
    if [ -n "$CURRENT_CRON" ]; then
        echo -e "\033[33mCurrent Backup Schedule:\033[0m $CURRENT_CRON"
    else
        echo -e "\033[33mNo active backup schedule found.\033[0m"
    fi

    echo -e "\033[36m1) Every Minute\033[0m"
    echo -e "\033[36m2) Every Hour\033[0m"
    echo -e "\033[36m3) Every Day\033[0m"
    echo -e "\033[36m4) Every Week\033[0m"
    echo -e "\033[36m5) Disable Backup\033[0m"
    echo -e "\033[36m6) Back to Menu\033[0m"
    echo ""
    read -p "Select an option [1-6]: " backup_option

    update_cron() {
        local cron_line="$1"
        if [ -n "$CURRENT_CRON" ]; then
            crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | crontab - && {
                echo -e "\033[92mRemoved previous backup schedule.\033[0m"
            } || {
                echo -e "\033[31mFailed to remove existing cron.\033[0m"
            }
        fi
        if [ -n "$cron_line" ]; then
            (crontab -l 2>/dev/null; echo "$cron_line") | crontab - && {
                echo -e "\033[92mBackup scheduled successfully.\033[0m"
                bash "$BACKUP_SCRIPT" &>/dev/null &
            } || {
                echo -e "\033[31mFailed to schedule backup.\033[0m"
            }
        fi
    }

    case $backup_option in
        1) update_cron "* * * * * bash $BACKUP_SCRIPT" ;;
        2) update_cron "0 * * * * bash $BACKUP_SCRIPT" ;;
        3) update_cron "0 0 * * * bash $BACKUP_SCRIPT" ;;
        4) update_cron "0 0 * * 0 bash $BACKUP_SCRIPT" ;;
        5)
            if [ -n "$CURRENT_CRON" ]; then
                crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | crontab - && {
                    echo -e "\033[92mAutomated backup disabled.\033[0m"
                } || {
                    echo -e "\033[31mFailed to disable backup.\033[0m"
                }
            else
                echo -e "\033[93mNo backup schedule to disable.\033[0m"
            fi
            ;;
        6) show_menu ;;
        *)
            echo -e "\033[31mInvalid option.\033[0m"
            auto_backup
            ;;
    esac
}

function renew_ssl() {
    echo -e "\033[33mStarting SSL renewal process...\033[0m"

    if ! command -v certbot &>/dev/null; then
        echo -e "\033[31m[ERROR]\033[0m Certbot is not installed. Please install Certbot to proceed."
        return 1
    fi

    echo -e "\033[33mStopping Apache...\033[0m"
    sudo systemctl stop apache2 || {
        echo -e "\033[31m[ERROR] Failed to stop Apache. Exiting...\033[0m"
        return 1
    }

    if sudo certbot renew; then
        echo -e "\033[32mSSL certificates successfully renewed.\033[0m"
    else
        echo -e "\033[31m[ERROR]\033[0m SSL renewal failed. Please check Certbot logs for more details."
        sudo systemctl start apache2
        return 1
    fi

    echo -e "\033[33mRestarting Apache...\033[0m"
    sudo systemctl restart apache2 || {
        echo -e "\033[31m[WARNING]\033[0m Failed to restart Apache. Please check manually."
    }

    echo -e "\033[32mSSL renewal completed successfully.\033[0m"
}

function change_domain() {
    local new_domain
    while [[ ! "$new_domain" =~ ^[a-zA-Z0-9.-]+$ ]]; do
        read -p "Enter new domain: " new_domain
        [[ ! "$new_domain" =~ ^[a-zA-Z0-9.-]+$ ]] && echo -e "\033[31mInvalid domain format\033[0m"
    done

    echo -e "\033[33mStopping Apache to configure SSL...\033[0m"
    if ! sudo systemctl stop apache2; then
        echo -e "\033[31m[ERROR] Failed to stop Apache!\033[0m"
        return 1
    fi

    echo -e "\033[33mConfiguring SSL for new domain...\033[0m"
    if ! sudo certbot --apache --redirect --agree-tos --non-interactive --preferred-challenges http -d "$new_domain"; then
        echo -e "\033[31m[ERROR] SSL configuration failed!\033[0m"
        echo -e "\033[33mCleaning up...\033[0m"
        sudo certbot delete --cert-name "$new_domain" 2>/dev/null
        echo -e "\033[33mRestarting Apache after cleanup...\033[0m"
        sudo systemctl start apache2 || echo -e "\033[31m[ERROR] Failed to restart Apache!\033[0m"
        return 1
    fi

    echo -e "\033[33mRestarting Apache after SSL configuration...\033[0m"
    if ! sudo systemctl start apache2; then
        echo -e "\033[31m[ERROR] Failed to restart Apache!\033[0m"
        return 1
    fi

    CONFIG_FILE="/var/www/html/zapzocketconfig/config.php"
    if [ -f "$CONFIG_FILE" ]; then
        sudo cp "$CONFIG_FILE" "$CONFIG_FILE.$(date +%s).bak"

        sudo sed -i "s|\$domainhosts = '.*\/zapzocketconfig';|\$domainhosts = '${new_domain}\/zapzocketconfig';|" "$CONFIG_FILE"

        NEW_SECRET=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')
        sudo sed -i "s|\$secrettoken = '.*';|\$secrettoken = '${NEW_SECRET}';|" "$CONFIG_FILE"

        BOT_TOKEN=$(awk -F"'" '/\$APIKEY/{print $2}' "$CONFIG_FILE")
        curl -s -o /dev/null -F "url=https://${new_domain}/zapzocketconfig/index.php" \
             -F "secret_token=${NEW_SECRET}" \
             "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" || {
            echo -e "\033[33m[WARNING] Webhook update failed\033[0m"
        }
    else
        echo -e "\033[31m[CRITICAL] Config file missing!\033[0m"
        return 1
    fi

    if curl -sI "https://${new_domain}" | grep -q "200 OK"; then
        echo -e "\033[32mDomain successfully migrated to ${new_domain}\033[0m"
        echo -e "\033[33mOld domain configuration has been automatically cleaned up\033[0m"
    else
        echo -e "\033[31m[WARNING] Final verification failed!\033[0m"
        echo -e "\033[33mPlease check:\033[0m"
        echo -e "1. DNS settings for ${new_domain}"
        echo -e "2. Apache virtual host configuration"
        echo -e "3. Firewall settings"
        return 1
    fi
}

function manage_additional_bots() {
    if [ ! -d "/var/www/html/zapzocketconfig" ]; then
        echo -e "\033[31m[ERROR]\033[0m The main ZapSocket Bot is not installed (/var/www/html/zapzocketconfig not found)."
        echo -e "\033[33mYou are not allowed to use this section without the main bot installed. Exiting...\033[0m"
        sleep 2
        exit 1
    fi

    if check_marzban_installed; then
        echo -e "\033[31m[ERROR]\033[0m Additional bot management is not available when Marzban is installed."
        echo -e "\033[33mExiting script...\033[0m"
        sleep 2
        exit 1
    fi

    echo -e "\033[36m1) Install Additional Bot\033[0m"
    echo -e "\033[36m2) Update Additional Bot\033[0m"
    echo -e "\033[36m3) Remove Additional Bot\033[0m"
    echo -e "\033[36m4) Export Additional Bot Database\033[0m"
    echo -e "\033[36m5) Import Additional Bot Database\033[0m"
    echo -e "\033[36m6) Configure Automated Backup for Additional Bot\033[0m"
    echo -e "\033[36m7) Back to Main Menu\033[0m"
    echo ""
    read -p "Select an option [1-7]: " sub_option
    case $sub_option in
        1) install_additional_bot ;;
        2) update_additional_bot ;;
        3) remove_additional_bot ;;
        4) export_additional_bot_database ;;
        5) import_additional_bot_database ;;
        6) configure_backup_additional_bot ;;
        7) show_menu ;;
        *)
            echo -e "\033[31mInvalid option. Please try again.\033[0m"
            manage_additional_bots
            ;;
    esac
}

function install_additional_bot() {
    echo -e "\033[33mAdditional bot installation feature coming soon...\033[0m"
    echo -e "\033[93mThis PRO feature allows you to run multiple bot instances.\033[0m"
}

function update_additional_bot() {
    echo -e "\033[33mAdditional bot update feature coming soon...\033[0m"
}

function remove_additional_bot() {
    echo -e "\033[33mAdditional bot removal feature coming soon...\033[0m"
}

function export_additional_bot_database() {
    echo -e "\033[33mAdditional bot database export feature coming soon...\033[0m"
}

function import_additional_bot_database() {
    echo -e "\033[33mAdditional bot database import feature coming soon...\033[0m"
}

function configure_backup_additional_bot() {
    echo -e "\033[33mAdditional bot backup configuration feature coming soon...\033[0m"
}

function remove_bot_with_marzban() {
    echo -e "\e[33mRemoving ZapSocket Bot (Marzban-compatible mode)...\033[0m"
    
    BOT_DIR="/var/www/html/zapzocketconfig"
    if [ -d "$BOT_DIR" ]; then
        sudo rm -rf "$BOT_DIR" && echo -e "\e[92mBot directory removed: $BOT_DIR\033[0m"
    fi

    if extract_db_credentials; then
        MYSQL_CONTAINER=$(docker ps -q --filter "name=mysql" --no-trunc)
        if [ -n "$MYSQL_CONTAINER" ]; then
            ENV_FILE="/opt/marzban/.env"
            MYSQL_ROOT_PASSWORD=$(grep "MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '[:space:]' | sed 's/"//g')
            
            docker exec "$MYSQL_CONTAINER" bash -c "mysql -u root -p'$MYSQL_ROOT_PASSWORD' -e \"DROP DATABASE IF EXISTS $DB_NAME; DROP USER IF EXISTS '$DB_USER'@'%'; FLUSH PRIVILEGES;\"" && {
                echo -e "\e[92mDatabase and user removed from Marzban MySQL.\033[0m"
            }
        fi
    fi

    echo -e "\e[92mZapSocket Bot removed successfully (Marzban mode).\033[0m"
}

# Main Execution
process_arguments() {
    local version=""
    case "$1" in
        -v*)
            version="${1#-v}"
            if [ -n "$version" ]; then
                install_bot "-v" "$version"
            else
                if [ -n "$2" ]; then
                    install_bot "-v" "$2"
                else
                    echo -e "\033[31m[ERROR]\033[0m Please specify a version with -v (e.g., -v 1.0.0)"
                    exit 1
                fi
            fi
            ;;
        -beta)
            install_bot "-beta"
            ;;
        --beta)
            install_bot "-beta"
            ;;
        -update)
            update_bot "$2"
            ;;
        *)
            show_menu
            ;;
    esac
}

if [ $# -eq 0 ]; then
    show_menu
else
    process_arguments "$1" "$2"
fi
