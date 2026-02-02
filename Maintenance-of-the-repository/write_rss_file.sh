python3.11 slint2slacklog.py /repo/x86_64/slint-15.0/ChangeLog.txt CleanChangeLog.txt
slacklog2rss --changelog CleanChangeLog.txt  \
--encoding utf-8 \
--out slint.rss \
--slackware "Slint"  \
--rssLink "https://slackware.uk/slint/x86_64/slint-15.0/slint.rss" \
--description "Slint activity"
