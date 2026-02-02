( cd usr/doc/python3-3.11.9 ; rm -rf Tools )
( cd usr/doc/python3-3.11.9 ; ln -sf /usr/lib64/python3.11/site-packages Tools )
( cd usr/lib64 ; rm -rf libpython3.11.so )
( cd usr/lib64 ; ln -sf libpython3.11.so.1.0 libpython3.11.so )
