package phrasesplit

import (
	"sort"
	"strings"
)

func Parse(phrases []string) map[string][]string {
	m := make(map[string][]string)
	for _, p := range phrases {
		word, rest, _ := strings.Cut(p, " ")
		m[word] = append(m[word], rest)
	}
	for _, s := range m {
		sort.Slice(s, func(i, j int) bool {
			return len(strings.Fields(s[i])) > len(strings.Fields(s[j]))
		})
	}
	return m
}

func Split(sentence string, phraseMap map[string][]string) ([]string, bool) {
	words := strings.Fields(sentence)
	var phrases, beforeBacktrack []string
	var forks []int
	i, backtrack := 0, false
	OUTER:
	for ; i < len(words) || backtrack; i++ {
		skip := 0
		if backtrack {
			if len(forks) == 0 {
				return beforeBacktrack, false
			}
			_, bad, _ := strings.Cut(phrases[len(phrases)-1], " ")
			i = forks[len(forks)-1]
			forks = forks[:len(forks)-1]
			phrases = phrases[:len(phrases)-1]
			for _, args := range phraseMap[words[i]] {
				skip++
				if args == bad {
					break
				}
			}
		}
		potentials, ok := phraseMap[words[i]]
		potentials = potentials[skip:]
		if ok {
			for _, args := range potentials {
				if args == "" {
					phrases = append(phrases, words[i])
					backtrack = false
					continue OUTER
				}
				n := strings.Count(args, " ") + 1
				if i + n >= len(words) {
					continue
				}
				if args == strings.Join(words[i+1:i+n+1], " ") {
					forks = append(forks, i)
					phrases = append(phrases, strings.Join(words[i:i+n+1], " "))
					i += n
					backtrack = false
					continue OUTER
				}
			}
		}
		if !backtrack {
			beforeBacktrack = phrases
		}
		backtrack = true
	}
	return phrases, true
}
