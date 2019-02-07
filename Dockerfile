FROM centos:centos7
MAINTAINER "Hiroki Takeyama"

# postfix
RUN yum -y install postfix cyrus-sasl-plain cyrus-sasl-md5 openssl; \
    sed -i 's/^\(inet_interfaces =\) .*/\1 all/' /etc/postfix/main.cf; \
    { \
    echo 'smtpd_sasl_path = smtpd'; \
    echo 'smtpd_sasl_auth_enable = yes'; \
    echo 'broken_sasl_auth_clients = yes'; \
    echo 'smtpd_sasl_security_options = noanonymous'; \
    echo 'smtpd_recipient_restrictions = permit_sasl_authenticated, reject_unauth_destination'; \
    } >> /etc/postfix/main.cf; \
    { \
    echo 'pwcheck_method: auxprop'; \
    echo 'auxprop_plugin: sasldb'; \
    echo 'mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5'; \
    } > /etc/sasl2/smtpd.conf; \
    sed -i 's/^#\(submission .*\)/\1/' /etc/postfix/master.cf; \
    sed -i 's/^#\(.*smtpd_sasl_auth_enable.*\)/\1/' /etc/postfix/master.cf; \
    sed -i 's/^#\(.*smtpd_recipient_restrictions.*\)/\1/' /etc/postfix/master.cf; \
    sed -i 's/^#\(smtps .*\)/\1/' /etc/postfix/master.cf; \
    sed -i 's/^#\(.*smtpd_tls_wrappermode.*\)/\1/' /etc/postfix/master.cf; \
    newaliases; \
    openssl genrsa -aes128 -passout pass:dummy -out "/etc/postfix/key.pass.pem" 2048; \
    openssl rsa -passin pass:dummy -in "/etc/postfix/key.pass.pem" -out "/etc/postfix/key.pem"; \
    rm -f "/etc/postfix/key.pass.pem"; \
    { \
    echo 'smtpd_tls_cert_file = /etc/postfix/cert.pem'; \
    echo 'smtpd_tls_key_file = /etc/postfix/key.pem'; \
    echo 'smtpd_tls_security_level = may'; \
    echo 'smtpd_tls_received_header = yes'; \
    echo 'smtpd_tls_loglevel = 1'; \
    echo 'smtp_tls_security_level = may'; \
    echo 'smtp_tls_loglevel = 1'; \
    echo 'smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache'; \
    echo 'tls_random_source = dev:/dev/urandom'; \
    } >> /etc/postfix/main.cf; \
    yum clean all;

# rsyslog
RUN yum -y install rsyslog; \
    sed -i 's/^\(\$SystemLogSocketName\) .*/\1 \/dev\/log/' /etc/rsyslog.d/listen.conf; \
    sed -i 's/^\(\$ModLoad imjournal\)/#\1/' /etc/rsyslog.conf; \
    sed -i 's/^\(\$OmitLocalLogging\) .*/\1 off/' /etc/rsyslog.conf; \
    sed -i 's/^\(\$IMJournalStateFile .*\)/#\1/' /etc/rsyslog.conf; \
    yum clean all;

# supervisor
RUN yum -y install epel-release; \
    yum -y --enablerepo=epel install supervisor; \
    sed -i 's/^\(nodaemon\)=false/\1=true/' /etc/supervisord.conf; \
    sed -i '/^\[unix_http_server\]$/a username=dummy' /etc/supervisord.conf; \
    sed -i '/^\[unix_http_server\]$/a password=dummy' /etc/supervisord.conf; \
    sed -i '/^\[supervisorctl\]$/a username=dummy' /etc/supervisord.conf; \
    sed -i '/^\[supervisorctl\]$/a password=dummy' /etc/supervisord.conf; \
    { \
    echo '[program:postfix]'; \
    echo 'command=/usr/sbin/postfix -c /etc/postfix start'; \
    echo 'startsecs=0'; \
    } > /etc/supervisord.d/postfix.ini; \
    { \
    echo '[program:rsyslog]'; \
    echo 'command=/usr/sbin/rsyslogd -n'; \
    } > /etc/supervisord.d/rsyslog.ini; \
    { \
    echo '[program:tail]'; \
    echo 'command=/usr/bin/tail -f /var/log/maillog'; \
    echo 'stdout_logfile=/dev/fd/1'; \
    echo 'stdout_logfile_maxbytes=0'; \
    } > /etc/supervisord.d/tail.ini; \
    yum clean all;

# entrypoint
RUN { \
    echo '#!/bin/bash -eu'; \
    echo 'rm -f /etc/localtime'; \
    echo 'ln -fs /usr/share/zoneinfo/${TIMEZONE} /etc/localtime'; \
    echo 'openssl req -new -key "/etc/postfix/key.pem" -subj "/CN=${HOST_NAME}" -out "/etc/postfix/csr.pem"'; \
    echo 'openssl x509 -req -days 36500 -in "/etc/postfix/csr.pem" -signkey "/etc/postfix/key.pem" -out "/etc/postfix/cert.pem" &>/dev/null'; \
    echo 'if [ -e /etc/sasldb2 ]; then'; \
    echo '  rm -f /etc/sasldb2'; \
    echo 'fi'; \
    echo 'echo "${AUTH_PASSWORD}" | /usr/sbin/saslpasswd2 -p -c -u ${DOMAIN_NAME} ${AUTH_USER}'; \
    echo 'chown postfix:postfix /etc/sasldb2'; \
    echo 'rm -f /var/log/maillog'; \
    echo 'touch /var/log/maillog'; \
    echo 'sed -i '\''/^# BEGIN SMTP SETTINGS$/,/^# END SMTP SETTINGS$/d'\'' /etc/postfix/main.cf'; \
    echo '{'; \
    echo 'echo "# BEGIN SMTP SETTINGS"'; \
    echo 'echo "myhostname = ${HOST_NAME}"'; \
    echo 'echo "mydomain = ${DOMAIN_NAME}"'; \
    echo 'echo "myorigin = \$mydomain"'; \
    echo 'echo "smtpd_banner = \$myhostname ESMTP unknown"'; \
    echo 'echo "message_size_limit = ${MESSAGE_SIZE_LIMIT}"'; \
    echo 'echo "# END SMTP SETTINGS"'; \
    echo '} >> /etc/postfix/main.cf'; \
    echo 'exec "$@"'; \
    } > /usr/local/bin/entrypoint.sh; \
    chmod +x /usr/local/bin/entrypoint.sh;
ENTRYPOINT ["entrypoint.sh"]

ENV TIMEZONE Asia/Tokyo

ENV HOST_NAME smtp.example.com
ENV DOMAIN_NAME example.com

ENV MESSAGE_SIZE_LIMIT 10240000

ENV AUTH_USER user
ENV AUTH_PASSWORD password

EXPOSE 25
EXPOSE 587

EXPOSE 465

CMD ["supervisord", "-c", "/etc/supervisord.conf"]
