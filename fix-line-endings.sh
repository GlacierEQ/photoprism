#!/bin/sh
# This script fixes line endings in bash scripts
# It converts CRLF line endings to LF

echo "Fixing line endings in shell scripts..."

# Fix the main deployment script
sed -i 's/\r$//' /app/scripts/deploy-production.sh
echo "Fixed deploy-production.sh"

# Fix any other scripts
find /app/scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} \;
echo "Fixed all .sh scripts in /app/scripts"

# Fix the start script
if [ -f /app/start.sh ]; then
  sed -i 's/\r$//' /app/start.sh
  echo "Fixed start.sh"
fi

echo "Line ending fixes completed."
