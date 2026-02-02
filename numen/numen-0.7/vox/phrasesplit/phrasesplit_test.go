package phrasesplit

import (
	"reflect"
	"testing"
)

func TestSplit1(t *testing.T) {
	phrases := []string{
		"air", "bat", "cap", "one", "two", "three", "three two one go",
		"go bananas", "go forward one", "go", "one more go", "one go", "go go",
	}
	sentence := "air bat cap go bananas go forward one one go go go go three two one go bananas"
	want := []string{
		"air", "bat", "cap", "go bananas", "go forward one", "one go",
		"go go", "go", "three", "two", "one", "go bananas",
	}

	got, ok := Split(sentence, Parse(phrases))
	if !ok {
		t.Fatal("failed to split")
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestSplit2(t *testing.T) {
	phrases := []string{"air", "bat", "cap", "dash scribe"}
	sentence := "air bat cap dash scribe dash air"
	want := []string{"air", "bat", "cap", "dash scribe"}

	got, ok := Split(sentence, Parse(phrases))
	if ok {
		t.Fatal("should have failed to split")
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestSplit3(t *testing.T) {
	phrases := []string{"air", "bat", "cap", "function one two three"}
	sentence := "air bat cap function one two three air"
	want := []string{"air", "bat", "cap", "function one two three", "air"}

	got, ok := Split(sentence, Parse(phrases))
	if !ok {
		t.Fatal("failed to split")
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}
