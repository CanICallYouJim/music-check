package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"unsafe"
)

var releaseGUIInstance = func() {}

func appWindowTitle() string {
	return "Проверка музыки"
}

func acquireGUIInstance() (bool, error) {
	name, _ := syscall.UTF16PtrFromString("Local\\IG.LenaDJ." + applicationMode)
	handle, _, err := syscall.NewLazyDLL("kernel32.dll").NewProc("CreateMutexW").Call(0, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return false, fmt.Errorf("запуск приложения: %w", err)
	}
	if err == syscall.ERROR_ALREADY_EXISTS {
		syscall.CloseHandle(syscall.Handle(handle))
		user := syscall.NewLazyDLL("user32.dll")
		for _, caption := range []string{appWindowTitle(), appWindowTitle() + " · проверка"} {
			title, _ := syscall.UTF16PtrFromString(caption)
			window, _, _ := user.NewProc("FindWindowW").Call(0, uintptr(unsafe.Pointer(title)))
			if window != 0 {
				user.NewProc("ShowWindow").Call(window, 9) // SW_RESTORE
				user.NewProc("SetForegroundWindow").Call(window)
				break
			}
		}
		return false, nil
	}
	var once sync.Once
	releaseGUIInstance = func() { once.Do(func() { syscall.CloseHandle(syscall.Handle(handle)) }) }
	return true, nil
}

func reportDialogError(err error) {
	reportAppError("Не удалось открыть окно программы.", "startup.log", err)
}

func reportUpdateError(action string, err error) {
	reportAppError("Не удалось "+action+" обновление. Текущая версия сохранена.", "update.log", err)
}

func reportAppError(explanation, logName string, err error) {
	message := explanation + "\n\n" + err.Error()
	if folder, e := os.UserCacheDir(); e == nil {
		folder = filepath.Join(folder, "LenaDJ", "MusicCheck")
		if os.MkdirAll(folder, 0700) == nil {
			log := filepath.Join(folder, logName)
			if os.WriteFile(log, []byte(message), 0600) == nil {
				message += "\n\nПодробности: " + log
			}
		}
	}
	if os.Getenv("CI") != "" {
		return
	}
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString(appWindowTitle())
	syscall.NewLazyDLL("user32.dll").NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
