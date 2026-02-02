# Update all the shared library links:
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig &
fi
