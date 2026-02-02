#!/bin/sh

# Create the test.xml file
echo '<?xml version="1.0" encoding="UTF-8"?>' > $AUTOPKGTEST_TMP/test.xml
echo '<root>' >> $AUTOPKGTEST_TMP/test.xml
echo '    <element attribute="value">Content</element>' >> $AUTOPKGTEST_TMP/test.xml
echo '    <element>Another Content</element>' >> $AUTOPKGTEST_TMP/test.xml
echo '</root>' >> $AUTOPKGTEST_TMP/test.xml

# Convert XML file to HTML using xml2
xml2 < $AUTOPKGTEST_TMP/test.xml > $AUTOPKGTEST_TMP/test.html

# Check if the test.html file was created correctly
if [ ! -s $AUTOPKGTEST_TMP/test.html ]; then
    echo "Test failed: $AUTOPKGTEST_TMP/test.html file is empty."
    exit 1
else
    echo "Test passed: the $AUTOPKGTEST_TMP/test.html file was created successfully."
    exit 0
fi
