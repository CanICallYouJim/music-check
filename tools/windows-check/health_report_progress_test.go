package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestHealthScanFilenameCannotForgeReportProgress(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows disallows newline in file names")
	}
	root := t.TempDir()
	name := "song\n[Отчёт 100%] forged.mp3"
	if err := os.WriteFile(filepath.Join(root, name), []byte("test bytes"), 0600); err != nil {
		t.Fatal(err)
	}
	var log bytes.Buffer
	report, err := scanHealth(context.Background(), root, false, "test", func(context.Context, string) (healthResult, error) { return healthyResult(), nil }, &log)
	if err != nil || strings.Contains(log.String(), "\n[Отчёт") || report.Tracks[0].Path != name {
		t.Fatalf("unsafe progress or changed path: %q %v", log.String(), err)
	}
}

func TestHealthReportProgressKeepsFilenameOnOneLine(t *testing.T) {
	var log bytes.Buffer
	logHealthReportProgress(&log)(healthReportProgress{Percent: 42, Done: 4, Total: 9, Path: "folder/name\n[Отчёт 100%].mp3", Phase: "Читаем звук"})
	if strings.Count(log.String(), "\n") != 1 || !strings.HasPrefix(log.String(), "[Отчёт 42%]") {
		t.Fatal("filename became a progress event")
	}
}

func TestHealthReportPlansOnlyVisibleUniqueRanges(t *testing.T) {
	engines, root, track := previewFixture(t)
	track.Result.Complete = true
	at, technical := 12.0, 18.0
	track.Result.Issues = []healthIssue{
		{Kind: "packet_gap", Severity: "warning", Start: &at},
		{Kind: "clipping", Severity: "warning", Start: &at},
		{Kind: "decoder_log", Severity: "info", Start: &technical},
	}
	var updates []healthReportProgress
	path, err := saveHealthReportWithPreviews(context.Background(), healthReport{Root: root, Fresh: 1, Tracks: []healthTrack{track}}, engines, func(p healthReportProgress) {
		if p.Percent == 100 {
			if _, err := os.Stat(pathForCurrentReport(root)); err != nil {
				t.Error("100% before HTML was published")
			}
		}
		updates = append(updates, p)
	})
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), "Готово фрагментов для прослушивания: 1 из 1") {
		t.Fatal("hidden or duplicate ranges became work")
	}
	if len(updates) < 3 || updates[0].Percent != 0 || updates[len(updates)-1].Percent != 100 {
		t.Fatalf("missing progress: %+v", updates)
	}
	previous := 0
	for i, p := range updates {
		if p.Percent < previous || p.Percent < 0 || p.Percent > 100 || (i < len(updates)-1 && p.Percent == 100) {
			t.Fatalf("false progress: %+v", updates)
		}
		previous = p.Percent
	}
}

func pathForCurrentReport(root string) string {
	paths, _ := filepath.Glob(filepath.Join(root, checkFolder, "Отчёт*.html"))
	if len(paths) == 0 {
		return filepath.Join(root, "not-yet-published")
	}
	return paths[len(paths)-1]
}

func TestHealthReportCancellationClearlyKeepsReadyPreview(t *testing.T) {
	engines, root, first := previewFixture(t)
	first.Result.Complete = true
	at := 12.0
	first.Result.Issues = []healthIssue{{Kind: "decode_error", Severity: "error", Start: &at}}
	second := first
	second.Path = "second.wav"
	other := 16.0
	second.Result.Issues = []healthIssue{{Kind: "decode_error", Severity: "error", Start: &other}}
	data, _ := os.ReadFile(filepath.Join(root, first.Path))
	if err := os.WriteFile(filepath.Join(root, second.Path), data, 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	report := healthReport{Root: root, Fresh: 2, Tracks: []healthTrack{first, second}}
	path, err := saveHealthReportWithPreviews(ctx, report, engines, func(p healthReportProgress) {
		if p.Path == second.Path {
			cancel()
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	text, _ := os.ReadFile(path)
	for _, want := range []string{"Подготовка фрагментов остановлена", "Готово фрагментов для прослушивания: 1 из 2", `data-preview-unavailable="true"`, `id="preview-0" hidden`} {
		if !strings.Contains(string(text), want) {
			t.Fatalf("partial report missing %s", want)
		}
	}
	if healthStats(report).Errors != 2 {
		t.Fatal("cancelled previews changed the sound diagnosis")
	}
}

func TestHealthReportNeverSaysCompleteAfterWriteFailure(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, checkFolder), []byte("blocked output"), 0600); err != nil {
		t.Fatal(err)
	}
	saidComplete := false
	_, err := writeHealthReport(context.Background(), healthReport{Root: root}, nil, func(p healthReportProgress) {
		if p.Percent == 100 {
			saidComplete = true
		}
	})
	if err == nil || saidComplete {
		t.Fatalf("failure shown as 100%%: %v %v", err, saidComplete)
	}
}
