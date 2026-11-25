package main

import (
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type healthReportProgress struct {
	Percent, Done, Total int
	Path, Phase          string
	Elapsed              int
}

func logHealthReportProgress(log io.Writer) func(healthReportProgress) {
	return func(p healthReportProgress) {
		name := filepath.Base(strings.ReplaceAll(p.Path, "\\", "/"))
		name = strings.NewReplacer("\n", " ", "\r", " ").Replace(name)
		if p.Path == "" {
			name = ""
		}
		phase := p.Phase
		if p.Elapsed > 0 {
			phase += fmt.Sprintf(" (идёт %d с)", p.Elapsed)
		}
		if name != "" {
			phase += " · " + name
		}
		if p.Total == 0 {
			fmt.Fprintf(log, "[Отчёт %d%%] %s\n", p.Percent, phase)
		} else {
			fmt.Fprintf(log, "[Отчёт %d%%] Обработано фрагментов: %d из %d. %s\n", p.Percent, p.Done, p.Total, phase)
		}
	}
}

// Keep a quiet long decode distinguishable from a frozen window. Callbacks are
// serialized, and the heartbeat is joined before the writer returns.
func healthReportNotifier(callbacks []func(healthReportProgress)) (func(healthReportProgress), func()) {
	if len(callbacks) == 0 {
		return func(healthReportProgress) {}, func() {}
	}
	var mu sync.Mutex
	var last healthReportProgress
	var since time.Time
	notify := func(p healthReportProgress) {
		for _, callback := range callbacks {
			if callback != nil {
				callback(p)
			}
		}
	}
	emit := func(p healthReportProgress) {
		mu.Lock()
		defer mu.Unlock()
		if p.Path != last.Path || p.Phase != last.Phase || since.IsZero() {
			since = time.Now()
		}
		last = p
		notify(p)
	}
	stop, done := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		tick := time.NewTicker(2 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-stop:
				return
			case <-tick.C:
				mu.Lock()
				if !since.IsZero() && last.Percent < 100 {
					p := last
					p.Elapsed = int(time.Since(since).Seconds())
					notify(p)
				}
				mu.Unlock()
			}
		}
	}()
	return emit, func() { close(stop); <-done }
}
