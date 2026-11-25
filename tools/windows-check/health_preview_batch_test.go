package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestHealthPreviewBatchProvidedBrokenIntervals(t *testing.T) {
	path := os.Getenv("MUSIC_CHECK_BROKEN_RECORDING")
	if path == "" {
		t.Skip("optional local damaged recording, never included in repository")
	}
	engines := testTools(t)
	before, err := fileFingerprint(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	verdict, err := engines.analyzeHealth(context.Background(), path)
	if err != nil || healthStatus(verdict) != "error" {
		t.Fatalf("damaged verdict lost: %+v %v", verdict, err)
	}
	faults := 0
	for _, issue := range verdict.Issues {
		if issue.Kind == "decode_error" && issue.Severity == "error" {
			faults++
		}
	}
	if faults != 7 {
		t.Fatalf("expected known 7 faults, got%d", faults)
	}
	root := t.TempDir()
	// Copy only into the test's temporary directory; never into published source.
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, "damaged.mp3"), data, 0600); err != nil {
		t.Fatal(err)
	}
	track := healthTrack{Path: "damaged.mp3", SHA256: before.Digest, Result: verdict}
	results := engines.healthPreviews(context.Background(), root, track, []float64{56.87, 61.75, 76.33, 110.34, 144.27, 163.81, 183.07}, nil)
	for i, result := range results {
		if result.Err != nil {
			t.Fatalf("damaged excerpt%d: %v", i, result.Err)
		}
		media, err := base64.StdEncoding.DecodeString(result.Preview.Data)
		if err != nil {
			t.Fatal(err)
		}
		clip := filepath.Join(t.TempDir(), "preview.mp3")
		if err = os.WriteFile(clip, media, 0600); err != nil {
			t.Fatal(err)
		}
		if output, err := exec.Command(engines.ffmpeg, "-v", "error", "-xerror", "-i", clip, "-f", "null", "-").CombinedOutput(); err != nil {
			t.Fatalf("unplayable excerpt%d: %v %s", i, err, output)
		}
		if math.Abs(float64(len(samples(t, engines.ffmpeg, clip)))/44100-9) > 1.0/44100 {
			t.Fatal("incorrect excerpt timeline")
		}
	}
	after, err := fileFingerprint(context.Background(), path)
	if err != nil || after.Digest != before.Digest {
		t.Fatal("damaged original changed")
	}
}

func countPreviewDecodes(t *testing.T, engines tools, source string) (tools, string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		return engines, ""
	} // The behavioral assertions also run on Windows.
	root := t.TempDir()
	log := filepath.Join(root, "decodes.log")
	wrapper := filepath.Join(root, "ffmpeg")
	script := `#!/bin/sh
source_read=0
outputs=0
for arg in "$@"; do
 if [ "$arg" = "$MC_BATCH_SOURCE" ]; then source_read=1; fi
 case "$arg" in *.nut) outputs=$((outputs + 1));; esac
done
if [ "$source_read" = 1 ]; then printf '%s\n' "$outputs" >> "$MC_BATCH_LOG"; fi
exec "$MC_BATCH_TOOL" "$@"
`
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MC_BATCH_SOURCE", source)
	t.Setenv("MC_BATCH_LOG", log)
	t.Setenv("MC_BATCH_TOOL", engines.ffmpeg)
	return tools{ffmpeg: wrapper, ffprobe: engines.ffprobe}, log
}

func TestHealthPreviewBatchDeduplicatesAndAligns(t *testing.T) {
	engines, root, track := previewFixture(t)
	source := filepath.Join(root, track.Path)
	original, _ := os.ReadFile(source)
	counted, log := countPreviewDecodes(t, engines, source)
	last := -1
	phases := map[string]int{}
	results := counted.healthPreviews(context.Background(), root, track, []float64{5, 12, 5, 16}, func(done, total int, phase string) {
		if total != 4 || done < last || done > total {
			t.Fatalf("bad progress %d/%d after%d", done, total, last)
		}
		last = done
		phases[phase]++
	})
	if len(results) != 4 || last != 4 {
		t.Fatalf("incomplete batch: %d progress%d", len(results), last)
	}
	for _, r := range results {
		if r.Err != nil {
			t.Fatal(r.Err)
		}
	}
	if results[0].Preview != results[2].Preview {
		t.Fatal("duplicate range produced different media")
	}
	if phases["Проверяем исходную запись"] != 1 || phases["Проверяем неизменность исходника"] != 1 {
		t.Fatalf("source validation repeated per preview: %+v", phases)
	}
	if log != "" {
		data, err := os.ReadFile(log)
		if err != nil || string(data) != "3\n" {
			t.Fatalf("expected one decode with three outputs: %s %v", data, err)
		}
	}
	raw, err := base64.StdEncoding.DecodeString(results[1].Preview.Data)
	if err != nil {
		t.Fatal(err)
	}
	clip := filepath.Join(t.TempDir(), "preview.mp3")
	if err = os.WriteFile(clip, raw, 0600); err != nil {
		t.Fatal(err)
	}
	x, y := samples(t, engines.ffmpeg, source), samples(t, engines.ffmpeg, clip)
	var xx, yy, xy float64
	for i := 4410; i < 44100; i++ {
		a, b := float64(x[7*44100+i]), float64(y[i])
		xx += a * a
		yy += b * b
		xy += a * b
	}
	if correlation := xy / math.Sqrt(xx*yy); correlation < .99 {
		t.Fatalf("batched excerpt shifted: %.6f", correlation)
	}
	after, _ := os.ReadFile(source)
	if !bytes.Equal(original, after) {
		t.Fatal("batch changed source")
	}
	cache, _ := filepath.Glob(filepath.Join(root, checkFolder, "previews", "*.json"))
	if len(cache) != 3 {
		t.Fatalf("duplicate cache entries: %d", len(cache))
	}
}

func TestHealthPreviewBatchBoundsOutputs(t *testing.T) {
	engines, root, track := previewFixture(t)
	counted, log := countPreviewDecodes(t, engines, filepath.Join(root, track.Path))
	targets := make([]float64, 17)
	for i := range targets {
		targets[i] = float64(i + 1)
	}
	results := counted.healthPreviews(context.Background(), root, track, targets, nil)
	for i, r := range results {
		if r.Err != nil {
			t.Fatalf("preview%d: %v", i, r.Err)
		}
	}
	if log != "" {
		data, err := os.ReadFile(log)
		if err != nil || string(data) != "16\n1\n" {
			t.Fatalf("decode output limit not respected: %s %v", data, err)
		}
	}
}

func TestHealthPreviewBatchInvalidatedSourceKeepsOldCache(t *testing.T) {
	engines, root, track := previewFixture(t)
	old, err := engines.healthPreview(context.Background(), root, track, 12)
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(root, track.Path)
	changed := false
	results := engines.healthPreviews(context.Background(), root, track, []float64{12, 16}, func(_, _ int, phase string) {
		if phase == "Проверяем неизменность исходника" && !changed {
			data, e := os.ReadFile(source)
			if e != nil {
				t.Fatal(e)
			}
			data[len(data)-8] ^= 1
			if e = os.WriteFile(source, data, 0600); e != nil {
				t.Fatal(e)
			}
			changed = true
		}
	})
	if !changed || results[0].Err != nil || results[0].Preview != old || results[1].Err == nil || results[1].Preview.Data != "" {
		t.Fatalf("unverified media escaped: %+v", results)
	}
	files, _ := filepath.Glob(filepath.Join(root, checkFolder, "previews", "*.json"))
	if len(files) != 1 {
		t.Fatal("unverified batch entered cache")
	}
}

func TestHealthPreviewBatchCancellationKeepsOldCache(t *testing.T) {
	engines, root, track := previewFixture(t)
	old, err := engines.healthPreview(context.Background(), root, track, 12)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	missing := tools{ffmpeg: "/missing/ffmpeg", ffprobe: "/missing/ffprobe"}
	results := missing.healthPreviews(ctx, root, track, []float64{12, 16}, nil)
	if results[0].Err != nil || results[0].Preview != old || !errors.Is(results[1].Err, context.Canceled) || results[1].Preview.Data != "" {
		t.Fatalf("cache/cancellation: %+v", results)
	}
	files, _ := filepath.Glob(filepath.Join(root, checkFolder, "previews", "*.json"))
	if len(files) != 1 {
		t.Fatal("cancelled batch entered cache")
	}
}

func TestHealthPreviewBatchMidGenerationCancellationDiscardsNew(t *testing.T) {
	engines, root, track := previewFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	results := engines.healthPreviews(ctx, root, track, []float64{5, 12}, func(done, _ int, phase string) {
		if done == 1 && phase == "Фрагмент обработан" {
			cancel()
		}
	})
	for _, r := range results {
		if !errors.Is(r.Err, context.Canceled) || r.Preview.Data != "" {
			t.Fatal("unverified preview survived cancellation")
		}
	}
	files, _ := filepath.Glob(filepath.Join(root, checkFolder, "previews", "*.json"))
	if len(files) != 0 {
		t.Fatal("cancelled group entered cache")
	}
}

func TestHealthPreviewBatchMixedInvalidRange(t *testing.T) {
	engines, root, track := previewFixture(t)
	results := engines.healthPreviews(context.Background(), root, track, []float64{math.NaN(), 12}, nil)
	if results[0].Err == nil || results[1].Err != nil || !strings.HasPrefix(results[1].Preview.Data, "/") {
		t.Fatalf("mixed ranges: invalid=%v valid=%v", results[0].Err, results[1].Err)
	}
}
