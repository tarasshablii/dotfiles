#!/usr/bin/env bats

setup() {
    DOTFILES="$BATS_TEST_DIRNAME/../dotfiles"
    
    # Sandbox Setup
    TEST_TEMP_DIR="$(mktemp -d)"
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME"
    
    # Configure git for the sandbox
    git config --global user.email "bats@test.com"
    git config --global user.name "Bats Test"
    git config --global init.defaultBranch main

    # Mock Remote Git Repo
    REMOTE_REPO="$TEST_TEMP_DIR/remote.git"
    git init --bare "$REMOTE_REPO" > /dev/null
}

teardown() {
    if [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

@test "'dotfiles init' fails without remote_url" {
    run "$DOTFILES" init
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Missing <remote_url> for init command." ]]
}

@test "'dotfiles init' aborts when backup exists and user declines overwrite" {
    # Create existing backup dir
    mkdir -p "$HOME/.dotfiles/backup"
    
    # Run with 'n' input
    run sh -c "echo n | $DOTFILES init \"$REMOTE_REPO\""
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Backup directory" ]] && [[ "$output" =~ "already exists" ]]
    [[ "$output" =~ "Aborting" ]]
}

@test "'dotfiles init' overwrites when backup exists and user accepts" {
    # Create existing backup dir with some content
    mkdir -p "$HOME/.dotfiles/backup"
    touch "$HOME/.dotfiles/backup/old_file"
    
    # Run with 'y' input
    run sh -c "echo y | $DOTFILES init \"$REMOTE_REPO\""
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Initializing backup repository" ]]
    
    # Verify old file is gone
    [ ! -f "$HOME/.dotfiles/backup/old_file" ]
    
    # Verify new repo structure
    [ -d "$HOME/.dotfiles/backup/.git" ]
}

@test "'dotfiles init' creates a fresh backup and pushes to remote" {
    run "$DOTFILES" init "$REMOTE_REPO"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Initializing backup repository" ]]
    [[ "$output" =~ "Pushing to remote" ]]
    [[ "$output" =~ "Backup repository initialized" ]]
    [[ "$output" =~ "Current profile: main" ]]

    # Check backup directory
    [ -d "$HOME/.dotfiles/backup/.git" ]
    
    # Check .current_profile
    [ -f "$HOME/.dotfiles/backup/.current_profile" ]
    run cat "$HOME/.dotfiles/backup/.current_profile"
    [ "$output" = "main" ]

    # Check git remote configuration
    cd "$HOME/.dotfiles/backup"
    run git remote get-url origin
    [ "$output" = "$REMOTE_REPO" ]
    
    # Check remote branch exists
    run git ls-remote --heads origin main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "refs/heads/main" ]]
}
