// Command pk-identity bootstraps and reports the Perkeep OpenPGP identity.
//
// Perkeep's server config needs an "identity" (a GPG key ID) that only exists
// once a secret keyring has been generated. That is a chicken-and-egg problem
// for a declaratively managed server-config.json: Terraform has to write the
// config before the container has ever run, so it cannot know the key ID.
//
// pk-identity closes the loop. Given a keyring path it generates a new identity
// if the keyring is absent, and prints the key ID either way. The entrypoint
// exports that value so the config can refer to it as
// ["_env", "${PERKEEP_IDENTITY}"], keeping the config file itself static.
//
// It is idempotent: an existing keyring is read, never regenerated.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"perkeep.org/pkg/jsonsign"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <secret-keyring-path>\n", filepath.Base(os.Args[0]))
		os.Exit(2)
	}
	ring := os.Args[1]

	_, err := os.Stat(ring)
	switch {
	case err == nil:
		keyID, err := jsonsign.KeyIdFromRing(ring)
		if err != nil {
			fmt.Fprintf(os.Stderr, "pk-identity: reading keyring %s: %v\n", ring, err)
			os.Exit(1)
		}
		fmt.Println(keyID)

	case os.IsNotExist(err):
		// GenerateNewSecRing opens with O_EXCL, so this cannot clobber a
		// keyring that appeared between the Stat and here.
		keyID, err := jsonsign.GenerateNewSecRing(ring)
		if err != nil {
			fmt.Fprintf(os.Stderr, "pk-identity: generating keyring %s: %v\n", ring, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "pk-identity: generated new identity %s in %s\n", keyID, ring)
		fmt.Println(keyID)

	default:
		fmt.Fprintf(os.Stderr, "pk-identity: stat %s: %v\n", ring, err)
		os.Exit(1)
	}
}
