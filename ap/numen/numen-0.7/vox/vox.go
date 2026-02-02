package vox

import (
	"encoding/json"
	"errors"
	"git.sr.ht/~geb/numen/vox/phrasesplit"
	"github.com/m7shapan/njson"
	"math"
	"strings"
	vosk "github.com/alphacep/vosk-api/go"
)

func init() {
	vosk.SetLogLevel(-1)
}

func NewModel(filepath string) (*vosk.VoskModel, error) {
	return vosk.NewModel(filepath)
}

type PhraseResult struct {
	Text string
	Confidence float64
	Start, End int
}

type Result struct {
	Text string
	Phrases []PhraseResult
	Confidence float64
	Valid, Partial bool
}

type Recognizer struct {
	VoskRecognizer *vosk.VoskRecognizer
	phraseMap map[string][]string
	sampleRate, byteDepth int
	bytesRead int
	Audio []byte
	finalized bool
	keyphrases bool
}

func NewRecognizer(model *vosk.VoskModel, sampleRate, bitDepth int, phrases []string) (*Recognizer, error) {
	if bitDepth % 8 != 0 {
		panic("bitDepth must be a multiple of eight")
	}
	var r *vosk.VoskRecognizer
	if phrases == nil {
		var err error
		r, err = vosk.NewRecognizer(model, float64(sampleRate))
		if err != nil {
			return nil, err
		}
	} else {
		j, err := json.Marshal(phrases)
		if err != nil {
			panic(err.Error())
		}
		r, err = vosk.NewRecognizerGrm(model, float64(sampleRate), string(j))
		if err != nil {
			return nil, err
		}
	}
	p := phrasesplit.Parse(phrases)
	return &Recognizer{r, p, sampleRate, bitDepth/8, 0, nil, false, false}, nil
}

func (r *Recognizer) Free() {
	r.VoskRecognizer.Free()
}

func (r *Recognizer) SetGrm(phrases []string) {
	j, err := json.Marshal(phrases)
	if err != nil {
		panic(err.Error())
	}
	audio := r.Audio
	r.Reset()
	r.VoskRecognizer.SetGrm(string(j))
	r.phraseMap = phrasesplit.Parse(phrases)
	r.Audio = audio
}
func (r *Recognizer) SetKeyphrases(b bool) {
	r.keyphrases = b
}
func (r *Recognizer) SetMaxAlternatives(n int) {
	r.VoskRecognizer.SetMaxAlternatives(n)
}
func (r *Recognizer) SetPartialWords(b bool) {
	if b {
		r.VoskRecognizer.SetPartialWords(1)
	} else {
		r.VoskRecognizer.SetPartialWords(0)
	}
}
func (r *Recognizer) SetWords(b bool) {
	if b {
		r.VoskRecognizer.SetWords(1)
	} else {
		r.VoskRecognizer.SetWords(0)
	}
}

func (r *Recognizer) index(time float64) int {
	rate := float64(r.sampleRate * r.byteDepth)
	i := time * rate - float64(r.bytesRead - len(r.Audio))
	// round to byteDepth multiple
	i = math.Round(i / float64(r.byteDepth)) * float64(r.byteDepth)

	if i < 0 {
		return 0
	}
	if int(i) > len(r.Audio) {
		return len(r.Audio)
	}
	return int(i)
}

func (r *Recognizer) parseVoskResults(json string) []Result {
	type ResultJson struct {
		Text string `njson:"text"`
		Words []string `njson:"result.#.word"`
		Confs []float64 `njson:"result.#.conf"`
		Starts []float64 `njson:"result.#.start"`
		Ends []float64 `njson:"result.#.end"`
		Confidence float64 `njson:"confidence"`  // only with alternatives
	}
	var s struct {
		Alternatives []ResultJson `njson:"alternatives"`

		// copy paste of ResultJson
		Text string `njson:"text"`
		Words []string `njson:"result.#.word"`
		Confs []float64 `njson:"result.#.conf"`
		Starts []float64 `njson:"result.#.start"`
		Ends []float64 `njson:"result.#.end"`
		Confidence float64 `njson:"confidence"`  // only with alternatives

		ParText string `njson:"partial"`
		ParWords []string `njson:"partial_result.#.word"`
		ParConfs []float64 `njson:"partial_result.#.conf"`
		ParStarts []float64 `njson:"partial_result.#.start"`
		ParEnds []float64 `njson:"partial_result.#.end"`
	}
	err := njson.Unmarshal([]byte(json), &s)
	if err != nil {
		panic(err)
	}

	if len(s.Alternatives) > 0 {
		results := make([]Result, len(s.Alternatives))
		for a := range s.Alternatives {
			results[a].Text = s.Alternatives[a].Text
			results[a].Confidence = s.Alternatives[a].Confidence
			results[a].Phrases = make([]PhraseResult, len(s.Alternatives[a].Words))
			for p := range results[a].Phrases {
				results[a].Phrases[p] = PhraseResult{
					s.Alternatives[a].Words[p],
					-1,  // conf isn't given
					r.index(s.Alternatives[a].Starts[p]),
					r.index(s.Alternatives[a].Ends[p]),
				}
			}
		}
		return results
	}
	if len(s.Text) > 0 {
		result := Result{Text: s.Text}
		result.Confidence = -1  // confidence isn't given
		result.Phrases = make([]PhraseResult, len(s.Words))
		for p := range result.Phrases {
			result.Phrases[p] = PhraseResult{
				s.Words[p], s.Confs[p],
				r.index(s.Starts[p]), r.index(s.Ends[p]),
			}
		}
		return []Result{result}
	}
	result := Result{Text: s.ParText, Partial: true}
	result.Confidence = -1  // confidence isn't given
	result.Phrases = make([]PhraseResult, len(s.ParWords))
	for p := range result.Phrases {
		result.Phrases[p] = PhraseResult{
			s.ParWords[p], s.ParConfs[p],
			r.index(s.ParStarts[p]), r.index(s.ParEnds[p]),
		}
	}
	return []Result{result}
}

func (r *Recognizer) parseResults(json string) []Result {
	if !r.keyphrases {
		return r.parseVoskResults(json)
	}
	results := r.parseVoskResults(json)
	for ri := range results {
		phrases, ok := phrasesplit.Split(results[ri].Text, r.phraseMap)
		results[ri].Valid = ok
		if len(results[ri].Phrases) > 0 && len(phrases) > 0 {
			n := strings.Count(strings.Join(phrases, " "), " ") + 1
			results[ri].Phrases = results[ri].Phrases[:n]
		} else {
			results[ri].Phrases = results[ri].Phrases[:0]
		}
		for pi := 0; pi < len(results[ri].Phrases) && len(phrases) > 0; pi++ {
			n := strings.Count(phrases[0], " ") + 1
			if n > 1 {
				text := results[ri].Phrases[pi].Text
				conf := results[ri].Phrases[pi].Confidence
				for _, p := range results[ri].Phrases[pi+1:pi+n] {
					text += " " + p.Text
					conf += p.Confidence
				}
				conf /= float64(n)
				start := results[ri].Phrases[pi].Start
				end := results[ri].Phrases[pi+n-1].End
				results[ri].Phrases = append(results[ri].Phrases[:pi+1], results[ri].Phrases[pi+n:]...)
				results[ri].Phrases[pi] = PhraseResult{text, conf, start, end}
			}
			phrases = phrases[1:]
		}
	}
	return results
}

func (r *Recognizer) Accept(audio []byte) (bool, error) {
	if r.finalized {
		r.Audio = nil
		r.finalized = false
	}
	if r.Audio == nil {
		// Prepending silence seems to help, especially when no required pause.
		audio = append(make([]byte, 4096), audio...)
	}
	r.bytesRead += len(audio)
	r.Audio = append(r.Audio, audio...)
	code := r.VoskRecognizer.AcceptWaveform(audio)
	if code == -1 {
		return false, errors.New("an exception occurred")
	}
	r.finalized = code == 1
	return r.finalized, nil
}

func (r *Recognizer) Results() []Result {
	if r.finalized {
		return r.parseResults(r.VoskRecognizer.Result())
	}
	return r.parseResults(r.VoskRecognizer.PartialResult())
}

func (r *Recognizer) FinalResults() []Result {
	r.finalized = true
	return r.parseResults(r.VoskRecognizer.FinalResult())
}

func (r *Recognizer) Reset() {
	r.VoskRecognizer.Reset()
	r.Audio = nil
}
