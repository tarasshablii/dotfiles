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

@test "'dotfiles pull' fails when backup repository does not exist" {
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" pull
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles pull' fails when local has changes (diverged) and cannot fast-forward" {
    init_backup_repo

    # Update remote with a new commit (C1 -> C2)
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch remote_file
    git add remote_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    # Update local with a divergent commit (C1 -> C3)
    cd "$BACKUP_DIR"
    touch local_file
    git add local_file
    git commit -m "Local divergent change" > /dev/null
    cd - > /dev/null

    run "$DOTFILES" pull
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Failed to pull changes from remote." ]]
    [[ "$output" =~ "remote has diverged" ]]
}

@test "'dotfiles pull' successfully pulls remote changes into local backup" {
    init_backup_repo

    # Update remote with a new commit (C1 -> C2)
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch remote_file
    git add remote_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    run "$DOTFILES" pull
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Local backup successfully synced with remote." ]]
    
    # Verify sync
    cd "$BACKUP_DIR"
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git ls-remote origin main | awk '{print $1}')
    [ "$local_hash" = "$remote_hash" ]
    
    # Verify file existence
    [ -f "remote_file" ]
}
