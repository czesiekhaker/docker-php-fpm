#!/bin/bash

# we need root
if [[ `whoami` != "root" ]]; then
  echo "we need root, and we are: $( whoami ); exiting!.."
  exit 1
fi

# sanity check
if [[ "$PHP_APP_NAME" == "" || "$PHP_APP_USER" == "" || "$PHP_APP_GROUP" == "" || "$PHP_APP_DIR" == "" ]]; then
  echo '$PHP_APP_NAME, $PHP_APP_USER, $PHP_APP_GROUP or $PHP_APP_DIR are not set'
  exit 2
fi

# info
echo "\$PHP_APP_NAME  :: $PHP_APP_NAME"
echo "\$PHP_APP_USER  :: $PHP_APP_USER"
echo "\$PHP_APP_GROUP :: $PHP_APP_GROUP"
echo "\$PHP_APP_DIR   :: $PHP_APP_DIR"
echo "\$PHP_LISTEN    :: $PHP_LISTEN"

# do we have UID/GID number given explicitly?
if [[ "$PHP_APP_UID" != "" ]]; then
  echo "\$PHP_APP_UID   :: $PHP_APP_UID"
fi
if [[ "$PHP_APP_GID" != "" ]]; then
  echo "\$PHP_APP_GID   :: $PHP_APP_GID"
fi

  
# get group data, if any
GROUP_DATA=`getent group "$PHP_APP_GROUP"`

# does the group exist?
if test $? -eq 0; then
  # it does! do we have the gid given?
  if [[ "$PHP_APP_GID" != "" ]]; then
    # we do! do these match?
    if [[ `echo "$GROUP_DATA" | cut -d ':' -f 3` != "$PHP_APP_GID" ]]; then
      # they don't. we have a problem
      echo "ERROR: group $PHP_APP_GROUP already exists, but with a different gid (`echo "$GROUP_DATA" | cut -d ':' -f 3`) than provided ($PHP_APP_GID)!"
      exit 3
    fi
  fi
  # if no gid given, the existing group satisfies us regardless of the GID

# group does not exist
else
  # do we have the gid given?
  GID_ARGS=""
  if [[ "$PHP_APP_GID" != "" ]]; then
    # we do! does a group with a given id exist?
    if `getent group "$PHP_APP_GID"`; then
      echo "ERROR: a group with a given id ($PHP_APP_GID) already exists, can't create group $PHP_APP_GROUP with this id"
      exit 4
    fi
    # prepare the fragment of the groupadd command
    GID_ARGS="-g $PHP_APP_GID"
  fi
  # we either have no GID given (and don't care about it), or have a GID given that does not exist in the system
  # great! let's add the group
  groupadd $GID_ARGS "$PHP_APP_GROUP"
fi

# get user data, if any
USER_DATA=`id -i "$PHP_APP_USER" 2>/dev/null`

# does the user exist?
if test $? -eq 0; then
  # it does! do we have the uid given?
  if [[ "$PHP_APP_UID" != "" ]]; then
    # we do! do these match?
    if [[ "$USER_DATA" != "$PHP_APP_UID" ]]; then
      # they don't. we have a problem
      echo "ERROR: user $PHP_APP_USER already exists, but with a different uid ("$USER_DATA") than provided ($PHP_APP_UID)!"
      exit 5
    fi
  fi
  # if no uid given, the existing user satisfies us regardless of the uid
  # but is he in the right group?
  adduser "$PHP_APP_USER" "$PHP_APP_GROUP"

# user does not exist
else
  # do we have the uid given?
  UID_ARGS=""
  if [[ "$PHP_APP_UID" != "" ]]; then
    # we do! does a group with a given id exist?
    if `getent passwd "$PHP_APP_UID"`; then
      echo "ERROR: a user with a given id ($PHP_APP_UID) already exists, can't create user $PHP_APP_USER with this id"
      exit 6
    fi
    # prepare the fragment of the useradd command
    UID_ARGS="-u $PHP_APP_UID"
  fi
  # we either have no UID given (and don't care about it), or have a UID given that does not exist in the system
  # great! let's add the user
  useradd $UID_ARGS -r -g "$PHP_APP_GROUP" "$PHP_APP_USER"
fi

# do we need particular packages installed?
if [ ! -z ${INSTALL_PACKAGES+x} ]; then
  # aye, install them
  DEBIAN_FRONTEND=noninteractive apt-get -q update && apt-get -q -y --no-install-recommends install $INSTALL_PACKAGES && apt-get -q clean && apt-get -q -y autoremove
fi

# log, run and data
mkdir -p /var/log/php-fpm
mkdir -p /var/run/php-fpm
mkdir -p $PHP_APP_DIR
chown $PHP_APP_USER:$PHP_APP_GROUP /var/log/php-fpm
chown $PHP_APP_USER:$PHP_APP_GROUP /var/run/php-fpm
chown $PHP_APP_USER:$PHP_APP_GROUP $PHP_APP_DIR

# PHP-FPM pool configuration.
# expects configuration in /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf file
if [ -s /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf ]; then
    echo "config file /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf found, ignoring any PHP_* env vars!"
else
    # if that file does not exist or is empty, it creates it with config from envvars
    echo "config file /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf not found, setting up from PHP_* env vars!"
    mv /etc/php5/fpm/pool.d/pool.conf /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf
    sed -i "s/pool_name/$PHP_APP_NAME/g" /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf
    sed -i "s/app_user/$PHP_APP_USER/g" /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf
    sed -i "s/app_group/$PHP_APP_GROUP/g" /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf
    sed -i -r -e "s/^listen = .*$/listen = $PHP_LISTEN" /etc/php5/fpm/pool.d/$PHP_APP_NAME.conf
fi

# Change the default error log location.
sed -i "s@error_log = /var/log/php5-fpm.log@error_log = '/dev/null'@g" /etc/php5/fpm/php-fpm.conf

# let's run the darn thing
exec /usr/sbin/php5-fpm -F --fpm-config /etc/php5/fpm/php-fpm.conf