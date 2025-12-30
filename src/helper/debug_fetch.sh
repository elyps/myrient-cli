#!/bin/bash
# Debug script to investigate get_links failure

BASE_URL="https://myrient.erista.me"

# A specific console path to test. Sony PlayStation is a good candidate.
TEST_PATH="/files/Redump/Sony%20-%20PlayStation/"

echo "1. Fetching raw HTML from ${BASE_URL}${TEST_PATH}..."
curl -v -s "${BASE_URL}${TEST_PATH}" > raw_page.html 2> curl_log.txt

if [ -s raw_page.html ]; then
    echo "   HTML fetched successfully ($(wc -c < raw_page.html) bytes)."
else
    echo "   FAILED to fetch HTML. See curl_log.txt"
    cat curl_log.txt
    exit 1
fi

echo "2. Inspecting first 20 lines of raw HTML containing 'href':"
grep "href" raw_page.html | head -n 20

echo "3. Testing current sed parsing logic..."
# Replicating the sed command from get_links
cat raw_page.html | \
sed -n -e '/<tr/!d' -e '/class="link"/!d' \
-e 's/.*<a href="\([^"]*\)"[^>]*>\([^<]*\)<\/a><\/td><td class="size">\([^<]*\)<\/td>.*/\1|\2|\3/p' > parsed_links.txt

echo "4. Parsed results (first 10 lines):"
head -n 10 parsed_links.txt

LINE_COUNT=$(wc -l < parsed_links.txt)
echo "   Total parsed items: $LINE_COUNT"

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "   ERROR: Parsing failed to extract any links."
    echo "   Dumping a snippet of the HTML table rows for inspection:"
    grep "<tr" raw_page.html | head -n 5
fi
