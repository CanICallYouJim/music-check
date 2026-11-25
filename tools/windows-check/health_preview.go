package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"time"
)

// A preview is independent MP3 media. Start and End refer to the source track.
type healthPreview struct {
	Data       string
	Start, End float64
}

const maxHealthPreviewBytes = 2 * 1024 * 1024

func healthPreviewRange(duration, target float64) (float64, float64, error) {
	if math.IsNaN(duration) || math.IsInf(duration, 0) || duration <= 0 || math.IsNaN(target) || math.IsInf(target, 0) {
		return 0, 0, errors.New("неверная длительность или таймкод фрагмента")
	}
	target = min(duration, max(0, target))
	start, end := max(0, target-5), min(duration, target+4)
	if target == 0 {
		end = min(duration, 8)
	}
	if end-start <= 0 {
		return 0, 0, errors.New("пустой фрагмент")
	}
	return start, end, nil
}

func readHealthPreview(path string, start, end float64) (healthPreview, bool) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxHealthPreviewBytes {
		return healthPreview{}, false
	}
	data, err := os.ReadFile(path)
	if err != nil || len(data) > maxHealthPreviewBytes {
		return healthPreview{}, false
	}
	var preview healthPreview
	if json.Unmarshal(data, &preview) != nil || preview.Start != start || preview.End != end {
		return healthPreview{}, false
	}
	media, err := base64.StdEncoding.DecodeString(preview.Data)
	if err != nil || len(media) < 4 || len(media) > maxHealthPreviewBytes || media[0] != 0xff || media[1]&0xe0 != 0xe0 {
		return healthPreview{}, false
	}
	return preview, true
}

type healthPreviewResult struct {
	Preview healthPreview
	Err     error
}

type previewJob struct {
	start, end float64
	cacheFile  string
	indexes    []int
	preview    healthPreview
	err        error
	counted    bool
}

func (t tools) healthPreview(ctx context.Context, root string, track healthTrack, target float64) (healthPreview, error) {
	result := t.healthPreviews(ctx, root, track, []float64{target}, nil)[0]
	return result.Preview, result.Err
}

// Validate a source once on each side of the entire group, instead of twice
// for every excerpt. A decoder feeds at most sixteen bounded PCM outputs.
func (t tools) healthPreviews(parent context.Context, root string, track healthTrack, targets []float64, onProgress func(done, total int, phase string)) []healthPreviewResult {
	results := make([]healthPreviewResult, len(targets))
	if len(targets) == 0 {
		return results
	}
	done := 0
	progress := func(phase string) {
		if onProgress != nil {
			onProgress(done, len(targets), phase)
		}
	}
	failAll := func(err error) []healthPreviewResult {
		for i := range results {
			results[i].Err = err
		}
		done = len(targets)
		progress("Не удалось подготовить фрагменты")
		return results
	}
	if !filepath.IsLocal(track.Path) {
		return failAll(errors.New("путь аудиофайла выходит за пределы библиотеки"))
	}
	if len(track.SHA256) != 64 {
		return failAll(errors.New("отсутствует SHA-256 исходной записи"))
	}
	if _, err := hex.DecodeString(track.SHA256); err != nil {
		return failAll(errors.New("неверный SHA-256 исходной записи"))
	}
	output := filepath.Join(root, checkFolder)
	if err := plainCheckDir(output); err != nil {
		return failAll(err)
	}
	cache := filepath.Join(output, "previews")
	if err := plainCheckDir(cache); err != nil {
		return failAll(err)
	}
	var jobs []*previewJob
	byKey := make(map[string]*previewJob)
	for i, target := range targets {
		start, end, err := healthPreviewRange(track.Result.Duration, target)
		if err != nil {
			results[i].Err = err
			done++
			progress("Неверный диапазон фрагмента")
			continue
		}
		key := sha256.Sum256([]byte(fmt.Sprintf("mp3-256-preview-2|%s|%.9f|%.9f", track.SHA256, start, end)))
		name := filepath.Join(cache, hex.EncodeToString(key[:])+".json")
		if job := byKey[name]; job != nil {
			job.indexes = append(job.indexes, i)
			continue
		}
		job := &previewJob{start: start, end: end, cacheFile: name, indexes: []int{i}}
		byKey[name] = job
		jobs = append(jobs, job)
	}
	finish := func(job *previewJob, phase string) {
		if !job.counted {
			done += len(job.indexes)
			job.counted = true
		}
		progress(phase)
	}
	var pending []*previewJob
	for _, job := range jobs {
		if preview, ok := readHealthPreview(job.cacheFile, job.start, job.end); ok {
			job.preview = preview
			finish(job, "Фрагмент из истории")
		} else {
			pending = append(pending, job)
		}
	}
	collect := func() []healthPreviewResult {
		for _, job := range jobs {
			for _, i := range job.indexes {
				results[i] = healthPreviewResult{job.preview, job.err}
			}
		}
		return results
	}
	if len(pending) == 0 {
		return collect()
	}
	failPending := func(err error) []healthPreviewResult {
		for _, job := range pending {
			job.preview = healthPreview{}
			job.err = err
			finish(job, "Фрагменты не подготовлены")
		}
		return collect()
	}
	ctx, cancel := context.WithTimeout(parent, 2*time.Minute)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return failPending(err)
	}
	source := filepath.Join(root, track.Path)
	progress("Проверяем исходную запись")
	before, err := fileFingerprint(ctx, source)
	if err != nil {
		return failPending(err)
	}
	if before.Digest != track.SHA256 {
		return failPending(errors.New("исходник изменился после проверки; фрагмент не создан"))
	}
	// PCM is temporary work, not library data: keep it off the USB drive.
	temp, err := os.MkdirTemp("", "music-preview-")
	if err != nil {
		return failPending(err)
	}
	defer os.RemoveAll(temp)
	const perPass = 16
	for base := 0; base < len(pending); base += perPass {
		if err = ctx.Err(); err != nil {
			return failPending(err)
		}
		batch := pending[base:min(base+perPass, len(pending))]
		progress("Читаем звук для фрагментов")
		args := []string{"-nostdin", "-v", "error", "-threads", "1", "-progress", "pipe:1", "-stats_period", "3600", "-i", source}
		for i, job := range batch {
			decoded := filepath.Join(temp, fmt.Sprintf("decoded-%d.nut", base+i))
			args = append(args, "-ss", fmt.Sprintf("%.9f", job.start), "-t", fmt.Sprintf("%.9f", job.end-job.start), "-map", "0:a:0", "-vn", "-map_metadata", "-1", "-map_chapters", "-1", "-filter_threads", "1", "-c:a", "pcm_f32le", "-ac", "2", "-ar", "44100", "-f", "nut", decoded)
		}
		_, err = runAudio(ctx, t.ffmpeg, args)
		if ctx.Err() != nil {
			return failPending(ctx.Err())
		}
		if err != nil {
			for _, job := range batch {
				job.err = fmt.Errorf("декодирование фрагмента: %w", err)
				finish(job, "Не удалось прочитать фрагмент")
			}
			continue
		}
		for i, job := range batch {
			if err = ctx.Err(); err != nil {
				return failPending(err)
			}
			progress("Создаём фрагмент для прослушивания")
			decoded := filepath.Join(temp, fmt.Sprintf("decoded-%d.nut", base+i))
			draft := filepath.Join(temp, fmt.Sprintf("audio-%d.mp3", base+i))
			job.preview, job.err = t.encodeHealthPreview(ctx, decoded, draft, job.start, job.end)
			_ = os.Remove(decoded)
			_ = os.Remove(draft)
			finish(job, "Фрагмент обработан")
		}
	}
	if err = ctx.Err(); err != nil {
		return failPending(err)
	}
	progress("Проверяем неизменность исходника")
	after, err := fileFingerprint(ctx, source)
	if err != nil {
		return failPending(err)
	}
	if after.Digest != before.Digest || !os.SameFile(before.Info, after.Info) {
		return failPending(errors.New("исходник изменился во время создания фрагментов"))
	}
	// Only media backed by the final full-file check may enter the cache/report.
	for _, job := range pending {
		if job.err == nil {
			if err = writeHealthPreview(cache, job.cacheFile, job.preview); err != nil {
				job.preview = healthPreview{}
				job.err = err
			}
		}
	}
	progress("Фрагменты проверены")
	return collect()
}

func (t tools) encodeHealthPreview(ctx context.Context, decoded, draft string, start, end float64) (healthPreview, error) {
	length := end - start
	pcmInfo, err := os.Stat(decoded)
	if err != nil || pcmInfo.Size() <= 0 || pcmInfo.Size() > 16*1024*1024 {
		return healthPreview{}, errors.New("недопустимый размер промежуточного фрагмента")
	}
	// Fill missing timestamp intervals with silence instead of collapsing the
	// timeline. This is a listening preview, not a repair of the source audio.
	filter := fmt.Sprintf("aresample=async=1:first_pts=0,apad=whole_dur=%.9f,atrim=duration=%.9f", length, length)
	_, err = runAudio(ctx, t.ffmpeg, []string{
		"-nostdin", "-v", "error", "-xerror", "-threads", "1", "-i", decoded,
		"-map", "0:a:0", "-vn", "-map_metadata", "-1", "-map_chapters", "-1",
		"-filter_threads", "1", "-af", filter, "-c:a", "libmp3lame", "-b:a", "256k", "-ac", "2", "-ar", "44100",
		"-id3v2_version", "0", "-write_id3v1", "0", "-progress", "pipe:1", "-stats_period", "3600", draft,
	})
	if err != nil {
		return healthPreview{}, fmt.Errorf("создание фрагмента: %w", err)
	}
	micros, err := runAudio(ctx, t.ffmpeg, []string{
		"-nostdin", "-v", "error", "-xerror", "-threads", "1", "-i", draft,
		"-map", "0:a:0", "-af", "asetpts=N/SR/TB", "-progress", "pipe:1", "-stats_period", "3600", "-f", "null", "-",
	})
	if err != nil || micros <= 0 || micros > 12_000_000 || math.Abs(float64(micros)/1e6-length) > .15 {
		return healthPreview{}, fmt.Errorf("не удалось проверить длительность фрагмента: %.6f с, ошибка %v", float64(micros)/1e6, err)
	}
	info, err := os.Stat(draft)
	if err != nil || info.Size() <= 0 || info.Size() > maxHealthPreviewBytes {
		return healthPreview{}, errors.New("недопустимый размер фрагмента")
	}
	media, err := os.ReadFile(draft)
	if err != nil {
		return healthPreview{}, err
	}
	preview := healthPreview{Data: base64.StdEncoding.EncodeToString(media), Start: start, End: end}
	return preview, nil
}

func writeHealthPreview(cache, cacheFile string, preview healthPreview) error {
	data, err := json.Marshal(preview)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(cache, ".preview-cache-*.tmp")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err = file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = os.Rename(name, cacheFile); err != nil {
		return err
	}
	return nil
}
