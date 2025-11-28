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

@test "'dotfiles backup' fails when backup repository does not exist" {
    # Ensure no backup dir exists
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" backup
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles backup' fails when local backup is behind remote" {
    init_backup_repo

    # Update remote with a new commit
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    run "$DOTFILES" backup
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
    [[ "$output" =~ "Please, run 'dotfiles pull' to update" ]]
}

@test "'dotfiles backup' aborts when current branch does not match profile" {
    init_backup_repo
    
    # Switch to a different branch in backup
    cd "$BACKUP_DIR"
    git checkout -b dev > /dev/null
    # .current_profile is still "main" from init_backup_repo
    cd - > /dev/null

    run sh -c "echo n | $DOTFILES backup"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "You are on branch 'dev', but the last applied profile was 'main'" ]]
    [[ "$output" =~ "Aborting" ]]
}

@test "'dotfiles backup' does nothing when no files are tracked" {
    init_backup_repo
    
    run "$DOTFILES" backup
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No files are tracked. Nothing to back up." ]]
}

@test "'dotfiles backup' reports no changes when files are up to date" {
    init_backup_repo
    
    touch "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    run "$DOTFILES" backup
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No changes to back up." ]]
}

@test "'dotfiles backup' keeps missing file in backup if user declines removal" {
    init_backup_repo
    
    touch "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    rm "$HOME/file1"
    
    run sh -c "echo n | $DOTFILES backup"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "The following tracked dotfiles not found in Home directory" ]]
    [[ "$output" =~ "- file1" ]]
    [[ "$output" =~ "Do you want to stop tracking them?" ]]
    
    # Verify file stays in backup
    [ -f "$BACKUP_DIR/files/file1" ]
}

@test "'dotfiles backup' removes missing file from backup if user accepts removal" {
    init_backup_repo
    
    touch "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    rm "$HOME/file1"
    
    run sh -c "echo y | $DOTFILES backup"
    
    [ "$status" -eq 0 ]
    
    # Verify file is removed from backup
    [ ! -f "$BACKUP_DIR/files/file1" ]
}

@test "'dotfiles backup' successfully backs up fresh changes" {
    init_backup_repo
    
    # Initial state
    echo "v1" > "$HOME/file1"
    run "$DOTFILES" add file1
    [ "$status" -eq 0 ]
    
    # Modify file in HOME
    echo "v2" > "$HOME/file1"
    
    run "$DOTFILES" backup
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Home dotfiles successfully backed up." ]]
    
    # Verify backup content
    run cat "$BACKUP_DIR/files/file1"
    [ "$output" = "v2" ]
    
    # Verify commit
    cd "$BACKUP_DIR"
    run git log -1 --pretty=%s
    [[ "$output" =~ "Backup" ]]
    
    # Verify push
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git ls-remote origin main | awk '{print $1}')
    [ "$local_hash" = "$remote_hash" ]
}
