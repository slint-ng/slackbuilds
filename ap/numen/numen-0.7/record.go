package main

import (
	"bytes"
	"io"
	"os"
	"os/exec"
)

func getMic(mic string) string {
	if mic == "" {
		out, _ := exec.Command("arecord", "-L").Output()
		if bytes.Contains(out, []byte("sysdefault:CARD=Microphone\n")) {
			mic = "sysdefault:CARD=Microphone"
		} else {
			mic = "default"
		}
	}
	return mic
}

func record(mic string) (io.Reader, error) {
	cmd := exec.Command("arecord", "-q", "-fS16_LE", "-c1", "-r16000", "-D", mic)
	cmd.Stderr = os.Stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	err = cmd.Start()
	if err != nil {
		return nil, err
	}
	return stdout, nil
}
