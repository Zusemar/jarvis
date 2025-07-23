package speech

import (
	"fmt"
	"os/exec"
	"strings"
)

func Recognize() (string, error) {
	cmd := exec.Command("python3", "../../scripts/recognize.py")
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Println("stderr:", string(out))
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func Say(text string) {
	exec.Command("say", text).Run()
}
