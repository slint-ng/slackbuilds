package main

import (
	"fmt"
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func getenv(key, fallback string) string {
	env := os.Getenv(key)
	if env == "" {
		return fallback
	}
	return env
}

func shell(cmd string) string {
	c := exec.Command(getenv("NUMEN_SHELL", "/bin/sh"), "-c", cmd)
	c.Stderr = os.Stderr
	out, err := c.Output()
	if err != nil {
		warn(err)
	}
	return strings.TrimSuffix(string(out), "\n")
}

func delay(ms, env string, def int, line string) int {
	ms = strings.TrimSpace(ms)
	w := "invalid argument:" + line
	if ms == "reset" {
		ms = os.Getenv(env)
		if ms == "" {
			return def
		}
		w = "invalid $" + env
	}
	n, err := strconv.Atoi(ms)
	if err != nil || n < 0 {
		warn(w)
		return def
	}
	return n
}

var (
	defaultKeyDelay = delay("2", "NUMEN_KEY_DELAY", 0, "")
	defaultKeyHold = delay("8", "NUMEN_KEY_HOLD", 0, "")
	defaultTypeDelay = delay("2", "NUMEN_TYPE_DELAY", 0, "")
	defaultTypeHold = delay("8", "NUMEN_TYPE_HOLD", 0, "")
)

type Handler interface {
	Cache(action string)
	Cached() string
	Chords(chords string) string
	Sticky() bool

	Caps(b bool)
	Click(button int)
	Keydown(chords string)
	Keyup(chords string)
	Load(files []string)
	Mod(mod string)
	MouseMove(x, y float64)
	MouseTo(x, y float64)
	Pen(cmd string)
	Press(chords string)
	Stick(b bool)
	Type(text string)
	Wheel(n int)
	Hwheel(n int)

	Keydelay(ms int)
	Keyhold(ms int)
	Typedelay(ms int)
	Typehold(ms int)

	Close()
}

func cutWord(s, word string) (string, bool) {
	if s == word {
		return "", true
	}
	if strings.HasPrefix(s, word + " ") || strings.HasPrefix(s, word + "\t") {
		return s[len(word)+1:], true
	}
	return "", false
}

func handle(handler *Handler, action string) {
	h := *handler
	for _, line := range strings.Split(action, "\n") {
		line = strings.TrimLeft(line, " \t")
		if s, ok := cutWord(line, "caps"); ok {
			s = strings.TrimSpace(s)
			if s == "on" {
				h.Caps(true)
			} else if s == "off" {
				h.Caps(false)
			} else {
				warn("invalid argument: " + line)
			}
		} else if s, ok := cutWord(line, "click"); ok {
			s = strings.TrimSpace(s)
			if s == "left" || s == "1" {
				h.Click(1)
			} else if s == "middle" || s == "2" {
				h.Click(2)
			} else if s == "right" || s == "3" {
				h.Click(3)
			} else {
				warn("unknown button: " + line)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "eval"); ok {
			handle(handler, shell(s))
		} else if s, ok := cutWord(line, "handler"); ok {
			s = strings.TrimSpace(s)
			if s == "gadget" {
				h.Close()
				*handler = NewGadgetHandler(h.Load)
				writeStateFile("handler", []byte(s))
			} else if s == "uinput" {
				h.Close()
				*handler = NewUinputHandler(h.Load)
				writeStateFile("handler", []byte(s))
			} else if s == "x11" {
				h.Close()
				*handler = NewX11Handler(h.Load)
				writeStateFile("handler", []byte(s))
			} else {
				warn("unknown handler: " + line)
			}
		} else if s, ok := cutWord(line, "keydown"); ok {
			h.Keydown(h.Chords(s))
		} else if s, ok := cutWord(line, "keyup"); ok {
			h.Keyup(h.Chords(s))
		} else if s, ok := cutWord(line, "load"); ok {
			h.Load(strings.Fields(s))
		} else if s, ok := cutWord(line, "mod"); ok {
			h.Mod(strings.TrimSpace(s))
		} else if s, ok := cutWord(line, "mousemove"); ok {
			s = strings.TrimSpace(s)
			var x, y float64
			_, err := fmt.Sscanf(s + "\n", "%f %f\n", &x, &y)
			if err == nil {
				h.MouseMove(x, y)
			} else {
				warn("invalid arguments: " + s)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "mouseto"); ok {
			s = strings.TrimSpace(s)
			var x, y float64
			_, err := fmt.Sscanf(s + "\n", "%f %f\n", &x, &y)
			if err == nil {
				h.MouseTo(x, y)
			} else {
				warn("invalid arguments: " + s)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "pen"); ok {
			h.Pen(s)
			h.Cache(line)
		} else if s, ok := cutWord(line, "press"); ok {
			chords := h.Chords(s)
			h.Press(chords)
			h.Mod("clear")
			h.Cache("press " + chords)
		} else if s, ok := cutWord(line, "repeat"); ok {
			times, err := strconv.Atoi(strings.TrimSpace(s))
			if err == nil {
				for i := 0; i < times; i++ {
					handle(handler, h.Cached())
				}
			} else {
				warn("invalid argument: " + line)
			}
		} else if s, ok := cutWord(line, "run"); ok {
			c := exec.Command(getenv("NUMEN_SHELL", "/bin/sh"), "-c", s)
			c.Stdout = os.Stdout
			c.Stderr = os.Stderr
			err := c.Run()
			if err != nil {
				warn(err)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "set"); ok {
			env, cmd, _ := strings.Cut(s, " ")
			os.Setenv(env, shell(cmd))
		} else if s, ok := cutWord(line, "stick"); ok {
			s = strings.TrimSpace(s)
			if s == "on" {
				h.Stick(true)
			} else if s == "off" {
				h.Stick(false)
			} else {
				warn("invalid argument: " + line)
			}
		} else if s, ok := cutWord(line, "type"); ok {
			h.Type(s)
			h.Cache(line)
		} else if s, ok := cutWord(line, "wheel"); ok {
			s = strings.TrimSpace(s)
			var n int
			_, err := fmt.Sscanf(s + "\n", "%d\n", &n)
			if err == nil {
				h.Wheel(n)
			} else {
				warn("invalid argument: " + s)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "hwheel"); ok {
			s = strings.TrimSpace(s)
			var n int
			_, err := fmt.Sscanf(s + "\n", "%d\n", &n)
			if err == nil {
				h.Hwheel(n)
			} else {
				warn("invalid argument: " + s)
			}
			h.Cache(line)
		} else if s, ok := cutWord(line, "keydelay"); ok {
			h.Keydelay(delay(s, "NUMEN_KEY_DELAY", defaultKeyDelay, line))
		} else if s, ok := cutWord(line, "keyhold"); ok {
			h.Keyhold(delay(s, "NUMEN_KEY_HOLD", defaultKeyHold, line))
		} else if s, ok := cutWord(line, "typedelay"); ok {
			h.Typedelay(delay(s, "NUMEN_TYPE_DELAY", defaultTypeDelay, line))
		} else if s, ok := cutWord(line, "typehold"); ok {
			h.Typehold(delay(s, "NUMEN_TYPE_HOLD", defaultTypeHold, line))
		} else if strings.TrimSpace(line) != "" {
			warn("unknown action: " + line)
		}
	}
}

func mods(mod string, super, ctrl, alt, shift bool) (bool, bool, bool, bool) {
	if mod == "super" {
		super = true
	} else if mod == "ctrl" {
		ctrl = true
	} else if mod == "alt" {
		alt = true
	} else if mod == "shift" {
		shift = true
	} else if mod == "clear" {
		super, ctrl, alt, shift = false, false, false, false
	} else {
		warn("unknown modifier: ", mod)
		return super, ctrl, alt, shift
	}
	s := fmt.Sprintln("super", super)
	s += fmt.Sprintln("ctrl", ctrl)
	s += fmt.Sprintln("alt", alt)
	s += fmt.Sprintln("shift", shift)
	writeStateFile("mods", []byte(s))
	return super, ctrl, alt, shift
}

type UinputHandler struct {
	dotool *exec.Cmd
	stdin io.WriteCloser
	load func(files []string)
	super, ctrl, alt, shift bool
	caps bool
	cache string
	stuck string
}

func NewUinputHandler(load func(files []string)) *UinputHandler {
	dotool := exec.Command("dotool")
	stdin, err := dotool.StdinPipe()
	if err != nil {
		fatal(err)
	}
	dotool.Stderr = os.Stderr
	if err := dotool.Start(); err != nil {
		fatal(err)
	}
	uh := &UinputHandler{dotool: dotool, stdin: stdin, load: load}
	uh.Keydelay(defaultKeyDelay)
	uh.Keyhold(defaultKeyHold)
	uh.Typedelay(defaultTypeDelay)
	uh.Typehold(defaultTypeHold)
	return uh
}

func (uh *UinputHandler) write(s string) {
	_, err := io.WriteString(uh.stdin, s + "\n")
	if err != nil {
		fatal(err)
	}
}

func (uh *UinputHandler) Cache(action string) {
	uh.cache = action
}
func (uh *UinputHandler) Cached() string {
	return uh.cache
}

func (uh *UinputHandler) Chords(chords string) string {
	var mods string
	if uh.super {
		mods += "super+"
	}
	if uh.ctrl {
		mods += "ctrl+"
	}
	if uh.alt {
		mods += "alt+"
	}
	if uh.shift {
		mods += "shift+"
	}
	s := ""
	for _, f := range strings.Fields(chords) {
		if i := strings.LastIndex(f, "+"); i >= 0 {
			f = f[:i+1] + "x:" + f[i+1:]
		} else {
			f = "x:" + f
		}
		f = strings.Replace(f, "x:x:", "x:", 1)
		s += mods + f + " "
	}
	return s
}

func (uh *UinputHandler) Sticky() bool {
	return uh.stuck != ""
}

func (uh *UinputHandler) Caps(b bool) {
	caps := uh.caps
	time.Sleep(time.Duration(50)*time.Millisecond)
	files, _ := filepath.Glob("/sys/class/leds/input*::capslock/brightness")
	for _, f := range files {
		data, _ := os.ReadFile(f)
		caps = bytes.ContainsRune(data, '1')
		if caps {
			break
		}
	}
	if caps != b {
		uh.write("key capslock")
	}
	uh.caps = b
}

func (uh *UinputHandler) Click(button int) {
	uh.write(fmt.Sprintln("click", button))
}

func (uh *UinputHandler) Keydown(chords string) {
	uh.write("keydown " + chords)
}
func (uh *UinputHandler) Keyup(chords string) {
	uh.write("keyup " + chords)
}

func (uh *UinputHandler) Load(files []string) {
	uh.load(files)
}

func (uh *UinputHandler) Mod(mod string) {
	uh.super, uh.ctrl, uh.alt, uh.shift = mods(mod, uh.super, uh.ctrl, uh.alt, uh.shift)
}

func (uh *UinputHandler) MouseMove(x, y float64) {
	uh.write(fmt.Sprintln("mousemove", x, y))
}
func (uh *UinputHandler) MouseTo(x, y float64) {
	uh.write(fmt.Sprintln("mouseto", x, y))
}

func (uh *UinputHandler) Pen(cmd string) {
	for i, line := range strings.Split(shell(cmd), "\n") {
		uh.write("type " + line)
		if i != 0 {
			uh.write("key enter")
		}
	}
}

func (uh *UinputHandler) Press(chords string) {
	if uh.stuck == "" {
		uh.write("key " + chords)
	} else {
		uh.write("keyup " + uh.stuck)
		uh.stuck = chords
		uh.write("keydown " + chords)
	}
}

func (uh *UinputHandler) Stick(b bool) {
	if b {
		uh.stuck = " "
	} else {
		uh.write("keyup " + uh.stuck)
		uh.stuck = ""
	}
}

func (uh *UinputHandler) Type(text string) {
	uh.write("type " + text)
}

func (uh *UinputHandler) Wheel(n int) {
	uh.write(fmt.Sprintln("wheel", n))
}
func (uh *UinputHandler) Hwheel(n int) {
	uh.write(fmt.Sprintln("hwheel", n))
}

func (uh *UinputHandler) Keydelay(ms int) {
	uh.write(fmt.Sprintln("keydelay", ms))
}
func (uh *UinputHandler) Keyhold(ms int) {
	uh.write(fmt.Sprintln("keyhold", ms))
}
func (uh *UinputHandler) Typedelay(ms int) {
	uh.write(fmt.Sprintln("typedelay", ms))
}
func (uh *UinputHandler) Typehold(ms int) {
	uh.write(fmt.Sprintln("typehold", ms))
}

func (uh *UinputHandler) Close() {
	if err := uh.stdin.Close(); err != nil {
		warn(err)
	}
	if err := uh.dotool.Wait(); err != nil {
		warn(err)
	}
}


type GadgetHandler struct {
	*UinputHandler
}

func NewGadgetHandler(load func(files []string)) *GadgetHandler {
	if _, err := exec.LookPath("gadget"); err != nil {
		fatal(`the gadget handler requires the gadget command:
    https://git.sr.ht/~geb/gadget`)
	}
	gadget := exec.Command("gadget")
	stdin, err := gadget.StdinPipe()
	if err != nil {
		fatal(err)
	}
	gadget.Stderr = os.Stderr
	if err := gadget.Start(); err != nil {
		fatal(err)
	}
	gh := &GadgetHandler{&UinputHandler{dotool: gadget, stdin: stdin, load: load}}
	gh.Keydelay(defaultKeyDelay)
	gh.Keyhold(defaultKeyHold)
	gh.Typedelay(defaultTypeDelay)
	gh.Typehold(defaultTypeHold)
	return gh
}

func (gh *GadgetHandler) Caps(b bool) {
	if gh.caps != b {
		gh.write("key capslock")
	}
	gh.caps = b
}


type X11Handler struct {
	load func(files []string)
	super, ctrl, alt, shift bool
	cache string
	stuck string
	keyDelay, keyHold, typeDelay, typeHold int
}

func NewX11Handler(load func(files []string)) *X11Handler {
	xh := &X11Handler{load: load}
	xh.Keydelay(defaultKeyDelay)
	xh.Keyhold(defaultKeyHold)
	xh.Typedelay(defaultTypeDelay)
	xh.Typehold(defaultTypeHold)
	return xh
}

func (xh *X11Handler) run(args ...string) {
	if _, err := exec.LookPath("xdotool"); err != nil {
		fatal("the x11 handler requires the xdotool command")
	}
	if _, err := exec.LookPath("xset"); err != nil {
		fatal("the x11 handler requires the xset command")
	}
	cmd := exec.Command("xdotool", args...)
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if err != nil {
		warn(err)
	}
}

func (xh *X11Handler) key(chords string) {
	d := fmt.Sprint(xh.keyDelay + xh.keyHold)
	xh.run(strings.Split("key --delay " + d + " -- " +  chords, " ")...)
}
func (xh *X11Handler) keydown(chords string) {
	d := fmt.Sprint(xh.keyDelay)
	xh.run(strings.Split("keydown --delay " + d + " -- " +  chords, " ")...)
}
func (xh *X11Handler) keyup(chords string) {
	d := fmt.Sprint(xh.keyDelay)
	xh.run(strings.Split("keyup --delay " + d + " -- " +  chords, " ")...)
}
func (xh *X11Handler) type_(text string) {
	d := fmt.Sprint((xh.typeDelay + xh.typeHold)*2)
	xh.run("type", "--delay", d, "--", text)
}

func (xh *X11Handler) Cache(action string) {
	xh.cache = action
}
func (xh *X11Handler) Cached() string {
	return xh.cache
}

func (xh *X11Handler) Chords(chords string) string {
	var mods string
	if xh.super {
		mods += "super+"
	}
	if xh.ctrl {
		mods += "ctrl+"
	}
	if xh.alt {
		mods += "alt+"
	}
	if xh.shift {
		mods += "shift+"
	}
	s := ""
	for _, f := range strings.Fields(chords) {
		s += mods + f + " "
	}
	return s
}

func (xh *X11Handler) Sticky() bool {
	return xh.stuck != ""
}

func (xh *X11Handler) Caps(b bool) {
	out, err := exec.Command("xset", "q").Output()
	if err != nil {
		warn(err)
		return
	}
	if bytes.Contains(out, []byte("Caps Lock:   off")) {
		if b {
			xh.key("Caps_Lock")
		}
	} else if bytes.Contains(out, []byte("Caps Lock:   on")) {
		if !b {
			xh.key("Caps_Lock")
		}
	} else {
		warn("bad xset output?!")
	}
}

func (xh *X11Handler) Click(button int) {
	xh.run("click", fmt.Sprint(button))
}

func (xh *X11Handler) Keydown(chords string) {
	xh.keydown(chords)
}
func (xh *X11Handler) Keyup(chords string) {
	xh.keyup(chords)
}

func (xh *X11Handler) Load(files []string) {
	xh.load(files)
}

func (xh *X11Handler) Mod(mod string) {
	xh.super, xh.ctrl, xh.alt, xh.shift = mods(mod, xh.super, xh.ctrl, xh.alt, xh.shift)
}

func xScreenDims() (int, int, bool) {
	cmd := exec.Command("xdotool", "search", "--maxdepth", "0", "--name", "", "getwindowgeometry")
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		warn(err)
	}

	_, geom, found := bytes.Cut(out, []byte("Geometry:"))
	if found {
		geom = bytes.TrimSpace(geom)
		width, height, found := bytes.Cut(geom, []byte("x"))
		if found {
			w, _ := strconv.Atoi(string(width))
			h, _ := strconv.Atoi(string(height))
			if w > 0 && h > 0 {
				return w, h, true
			}
		}
	}
	warn("bad xdotool geometry output?!")
	return 0, 0, false
}

func (xh *X11Handler) MouseMove(x, y float64) {
	xh.run("mousemove", "--relative", "--", fmt.Sprint(x), fmt.Sprint(y))
}
func (xh *X11Handler) MouseTo(x, y float64) {
	w, h, ok := xScreenDims()
	if ok {
		x *= float64(w)
		y *= float64(h)
		xh.run("mousemove", "--", fmt.Sprint(x), fmt.Sprint(y))
	}
}

func (xh *X11Handler) Pen(cmd string) {
	for i, line := range strings.Split(shell(cmd), "\n") {
		xh.type_(line)
		if i != 0 {
			xh.run("key", "Return")
		}
	}
}

func (xh *X11Handler) Press(chords string) {
	if xh.stuck == "" {
		xh.key(chords)
	} else {
		xh.keyup(xh.stuck)
		xh.stuck = chords
		xh.keydown(chords)
	}
}

func (xh *X11Handler) Stick(b bool) {
	if b {
		xh.stuck = " "
	} else {
		xh.run("keyup", "--delay", fmt.Sprint(xh.keyDelay), "--", xh.stuck)
		xh.stuck = ""
	}
}

func (xh *X11Handler) Type(text string) {
	xh.type_(text)
}

func (xh *X11Handler) Wheel(n int) {
	if n < 0 {
		xh.run("click", "--repeat", fmt.Sprint(-n), "5")
	} else if n > 0 {
		xh.run("click", "--repeat", fmt.Sprint(n), "4")
	}
}
func (xh *X11Handler) Hwheel(n int) {
	if n < 0 {
		xh.run("click", "--repeat", fmt.Sprint(-n), "6")
	} else if n > 0 {
		xh.run("click", "--repeat", fmt.Sprint(n), "7")
	}
}

func (xh *X11Handler) Keydelay(ms int) {
	xh.keyDelay = ms
}
func (xh *X11Handler) Keyhold(ms int) {
	xh.keyHold = ms
}
func (xh *X11Handler) Typedelay(ms int) {
	xh.typeDelay = ms
}
func (xh *X11Handler) Typehold(ms int) {
	xh.typeHold = ms
}

func (xh *X11Handler) Close() {
	xh.keyup("super control alt shift c")
}
