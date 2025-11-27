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

    # Mock Remote Git Repo (Prepare a valid repo to clone from)
    REMOTE_BARE="$TEST_TEMP_DIR/remote.git"
    git init --bare "$REMOTE_BARE" > /dev/null
    
    # Create a source repo to push content to the remote
    SOURCE_REPO="$TEST_TEMP_DIR/source"
    git init "$SOURCE_REPO" > /dev/null
    cd "$SOURCE_REPO"
    touch .gitignore
    git add .gitignore
    git commit -m "Initial commit" > /dev/null
    git remote add origin "$REMOTE_BARE"
    git push -u origin main > /dev/null
    cd - > /dev/null
}

teardown() {
    if [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

@test "'dotfiles install' fails without remote_url" {
    run "$DOTFILES" install
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Missing <remote_url> for install command." ]]
}

@test "'dotfiles install' aborts when backup exists and user declines overwrite" {
    # Create existing backup dir
    mkdir -p "$HOME/.dotfiles/backup"
    
    # Run with 'n' input
    run sh -c "echo n | $DOTFILES install \"$REMOTE_BARE\""
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Backup directory" ]] && [[ "$output" =~ "already exists" ]]
    [[ "$output" =~ "Aborting install" ]]
}

@test "'dotfiles install' overwrites when backup exists and user accepts" {
    # Create existing backup dir with a file to ensure it gets nuked
    mkdir -p "$HOME/.dotfiles/backup"
    touch "$HOME/.dotfiles/backup/garbage_file"
    
    # Run with 'y' input
    run sh -c "echo y | $DOTFILES install \"$REMOTE_BARE\""
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Backup directory" ]] && [[ "$output" =~ "already exists" ]]
    [[ "$output" =~ "Overwriting existing directory" ]]
    [[ "$output" =~ "Successfully installed dotfiles" ]]
    
    # Garbage file should be gone
    [ ! -f "$HOME/.dotfiles/backup/garbage_file" ]
    
    # Should be a valid git repo now
    [ -d "$HOME/.dotfiles/backup/.git" ]
    [ -f "$HOME/.dotfiles/backup/.gitignore" ]
}

@test "'dotfiles install' successfully clones remote repo" {
    run "$DOTFILES" install "$REMOTE_BARE"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Cloning profile 'main'" ]]
    [[ "$output" =~ "Successfully installed dotfiles" ]]
    [[ "$output" =~ "Current profile: main" ]]

    # Verify repo
    [ -d "$HOME/.dotfiles/backup/.git" ]
    [ -f "$HOME/.dotfiles/backup/.gitignore" ]
    
    # Verify .current_profile
    [ -f "$HOME/.dotfiles/backup/.current_profile" ]
    run cat "$HOME/.dotfiles/backup/.current_profile"
    [ "$output" = "main" ]
    
    # Verify remote origin is correct
    cd "$HOME/.dotfiles/backup"
    run git remote get-url origin
    [ "$output" = "$REMOTE_BARE" ]
}
