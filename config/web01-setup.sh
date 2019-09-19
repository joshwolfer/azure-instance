#!/bin/sh
# Deploys NGINX

# cd /tmp
apt-get -y update > /dev/null 2>&1
apt install -y nginx > /dev/null 2>&1

cat << EOF > /var/www/html/index.nginx-debian.html
<html>
  <head><title>Wolfer Terraform Demo!</title></head>
  Hello from Web01!
  </body>
</html>
EOF

echo "Provisioning Complete!"
