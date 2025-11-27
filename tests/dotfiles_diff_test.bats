#!/usr/bin/env bats

setup() {
    DOTFILES="$BATS_TEST_DIRNAME/../dotfiles"
    
    # Sandbox Setup
    TEST_TEMP_DIR="$(mktemp -d)"
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME"
    
    BACKUP_DIR="$HOME/.dotfiles/backup"
    
    # Configure git
    git config --global user.email "bats@test.com"
    git config --global user.name "Bats Test"
    git config --global init.defaultBranch main

    # Remote Repo
    REMOTE_REPO="$TEST_TEMP_DIR/remote.git"
    git init --bare "$REMOTE_REPO" > /dev/null
}

teardown() {
    if [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

init_backup_repo() {
    local source_repo="$TEST_TEMP_DIR/source"
    mkdir -p "$source_repo"
    cd "$source_repo"
    git init > /dev/null
    touch .gitignore
    git add .gitignore
    git commit -m "Initial commit" > /dev/null
    git remote add origin "$REMOTE_REPO"
    git push -u origin main > /dev/null
    cd - > /dev/null

    git clone "$REMOTE_REPO" "$BACKUP_DIR" > /dev/null 2>&1
    
    echo "main" > "$BACKUP_DIR/.current_profile"
}

@test "'dotfiles diff' fails when backup repository does not exist" {
    # Ensure no backup dir exists
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" diff
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles diff' shows message when no files are tracked" {
    init_backup_repo
    
    run "$DOTFILES" diff
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No files are tracked. Nothing to diff." ]]
}

@test "'dotfiles diff' shows message when all files are in sync" {
    init_backup_repo
    
    echo "content" > "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    run "$DOTFILES" diff
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "All tracked files are in sync." ]]
}

@test "'dotfiles diff' displays differences for changed file" {
    init_backup_repo
    
    echo "original content" > "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    # Modify the file in HOME
    echo "new content" > "$HOME/file1"
    
    run "$DOTFILES" diff
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "--- a/files/file1" ]]
    [[ "$output" =~ "+++ b/file1" ]]
    [[ "$output" =~ "-original content" ]]
    [[ "$output" =~ "+new content" ]]
}
