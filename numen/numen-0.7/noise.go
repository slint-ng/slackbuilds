package main

import (
	"github.com/mjibson/go-dsp/fft"
	"github.com/mjibson/go-dsp/wav"
	"github.com/mjibson/go-dsp/window"
	"io"
	"math"
	"os"
	"strconv"
)

const wavHeader = "RIFF$\x00\x00\x80WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80>\x00\x00\x00}\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x80"

var noiseThreshold float64
func init() {
	e := os.Getenv("NUMEN_NOISE_THRESHOLD")
	noiseThreshold, _ = strconv.ParseFloat(e, 64)
	if e != "" && noiseThreshold <= 0.0 {
		warn("invalid $NUMEN_NOISE_THRESHOLD")
	}
	if noiseThreshold <= 0.0 {
		noiseThreshold = 1.0
	}
}

type Noise int
const (
	NoiseNone Noise = iota
	NoiseBlow
	NoiseHiss
	NoiseShush
)

func noiseBeginString(n Noise) string {
	switch n {
	case NoiseBlow: return "<blow-begin>"
	case NoiseHiss: return "<hiss-begin>"
	case NoiseShush: return "<shush-begin>"
	}
	return ""
}
func noiseEndString(n Noise) string {
	switch n {
	case NoiseBlow: return "<blow-end>"
	case NoiseHiss: return "<hiss-end>"
	case NoiseShush: return "<shush-end>"
	}
	return ""
}

type NoiseRecognizer struct {
	r io.Reader
	decoder *wav.Wav
	Blow, Hiss, Shush bool
	PrevNoise, Noise Noise
}

func NewNoiseRecognizer(r io.Reader, blow, hiss, shush bool) *NoiseRecognizer {
	return &NoiseRecognizer{r, nil, blow, hiss, shush, NoiseNone, NoiseNone}
}

func (nr *NoiseRecognizer) Proceed(n int) {
	if nr.decoder == nil {
		var err error
		nr.decoder, err = wav.New(nr.r)
		if err != nil {
			fatal(err)
		}
		n -= 44
	}

	chunk, err := nr.decoder.ReadFloats(n)
	if err != nil {
		panic(err)
	}

	windowed := make([]float64, len(chunk))
	for i := range windowed {
		windowed[i] = float64(chunk[i])
	}
	window.Apply(windowed, window.Blackman)

	spectrum := fft.FFTReal(windowed)

	energy := 0.0
	for i := 3; i < 1333; i++ {
		energy += real(spectrum[i]) *  real(spectrum[i])
	}

	centroid := 0.0
	for i := 3; i < 1333; i++ {
		centroid += float64(i) * real(spectrum[i]) * real(spectrum[i])
	}
	centroid /= energy

	moment2 := 0.0
	moment3 := 0.0
	for i := 3; i < 1333; i++ {
		moment2 += math.Pow(float64(i) - centroid, 2) * real(spectrum[i]) * real(spectrum[i]);
		moment3 += math.Pow(float64(i) - centroid, 3) * real(spectrum[i]) * real(spectrum[i]);
	}
	moment2 /= energy
	moment3 /= energy

	skewness := moment3 / math.Pow(math.Sqrt(moment2), 3)

	rolloff := 3
	{
		rollsum := 0.0
		for rollsum < energy * 0.95 && rolloff < 1333 {
			rollsum += real(spectrum[rolloff]) * real(spectrum[rolloff])
			rolloff++
		}
	}

	buzz := 0.0
	for i := 3; i < 222; i++ {
		buzz += real(spectrum[i]) * real(spectrum[i])
	}
	buzz /= energy

	whisp := 0.0
	for i := 711; i < 1333; i++ {
		whisp += real(spectrum[i]) * real(spectrum[i])
	}
	whisp /= energy

	fuzz := 0.0
	for i := 3; i < 29; i++ {
		a := real(spectrum[i])
		b := real(spectrum[i+1])
		fuzz += math.Abs(a - b) * math.Abs(a - b)
	}

	over := 0
	for i := 3; i < 30; i++ {
		a := real(spectrum[i]) * real(spectrum[i])
		if a > math.Sqrt(energy)/4 * noiseThreshold {
			over++
		}
	}

	var blow, hiss, shush bool
	if energy > 500.0 * noiseThreshold {
		blow = fuzz > 500.0 * noiseThreshold && over > 10 && rolloff < 55 && centroid > 8.0
	}
	if energy > 5.0 * noiseThreshold {
		hiss = whisp > 0.82 && skewness > -2.7 && skewness < -0.3 && buzz < 0.021
		shush = whisp > 0.24 && whisp < 0.8 && skewness > -0.4 && skewness < 1.65 && moment2 > 96000.0 && buzz < 0.07
	}
	var blowMore, hissMore, shushMore bool
	if energy > 1.0 * noiseThreshold {
		blowMore = fuzz > 80.0 * noiseThreshold
		hissMore = whisp > 0.6 && skewness > -2.7 && skewness < -0.15
		shushMore = whisp > 0.1 && whisp < 0.9 && skewness > -0.5 && skewness < 1.8
	}

	nr.PrevNoise = nr.Noise
	if nr.Noise == NoiseBlow && blowMore {
		nr.Noise = NoiseBlow
	} else if nr.Noise == NoiseHiss && hissMore {
		nr.Noise = NoiseHiss
	} else if nr.Noise == NoiseShush && shushMore {
		nr.Noise = NoiseShush
	} else if nr.Blow && blow {
		nr.Noise = NoiseBlow
	} else if nr.Hiss && hiss {
		nr.Noise = NoiseHiss
	} else if nr.Shush && shush {
		nr.Noise = NoiseShush
	} else {
		nr.Noise = NoiseNone
	}
}
