#for i in pdf-core prawn prawn-icon prawn-svg prawn-table safe_yaml thread-safe treetop ttfunk; do
for i in afm asciidoctor; do
	mkdir -p ../rubygem-$i
	cp rubygem-template.SlackBuild ../rubygem-$i/rubygem-$i.SlackBuild
echo "rubygem-${i}: rubygem-${i} ()" >../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}: To know more visit: https://rubygems.org/search?query=$i">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc
echo "rubygem-${i}:">>../rubygem-$i/slack-desc

done
