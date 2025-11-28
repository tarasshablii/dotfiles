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

@test "'dotfiles rm' fails when backup repository does not exist" {
    # Ensure no backup dir exists
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" rm some_file
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles rm' fails when missing required argument" {
    init_backup_repo

    run "$DOTFILES" rm
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Missing <path>(s) for rm command." ]]
    [[ "$output" =~ "Usage: dotfiles <command> [options]" ]]
}

@test "'dotfiles rm' fails when local backup is behind remote" {
    init_backup_repo

    # Update remote with a new commit
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    # Create a file in HOME to attempt to remove (even if it's not tracked yet, safety check runs first)
    touch "$HOME/test_file"

    run "$DOTFILES" rm test_file
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
    [[ "$output" =~ "Please, run 'dotfiles pull' to update" ]]
}

@test "'dotfiles rm' aborts when current branch does not match profile" {
    init_backup_repo
    
    # Switch to a different branch in backup
    cd "$BACKUP_DIR"
    git checkout -b dev > /dev/null
    # .current_profile is still "main" from init_backup_repo
    cd - > /dev/null

    # Create a file in HOME to attempt to remove
    touch "$HOME/test_file"

    run sh -c "echo n | $DOTFILES rm test_file"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "You are on branch 'dev', but the last applied profile was 'main'" ]]
    [[ "$output" =~ "Aborting" ]]
}

@test "'dotfiles rm' reports error for file outside HOME directory" {
    init_backup_repo
    
    # Create file in the temp dir (parent of HOME)
    touch "$TEST_TEMP_DIR/outside_home_file"
    
    # Use relative path traversing up from HOME
    run "$DOTFILES" rm "../outside_home_file"
    
    # Expect status 0, but error message in output
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Could not remove" ]]
    [[ "$output" =~ "Path is not inside the home directory." ]]
}

@test "'dotfiles rm' reports error for file not tracked in backup" {
    init_backup_repo
    
    run "$DOTFILES" rm untracked_file
    
    # Expect status 0, but error message in output
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Could not remove" ]]
    [[ "$output" =~ "untracked_file': Not tracked." ]]
}

@test "'dotfiles rm' successfully removes single file (HOME is not affected)" {
    init_backup_repo
    
    touch "$HOME/file_to_remove"
    run "$DOTFILES" add file_to_remove
    [ "$status" -eq 0 ]
    
    run "$DOTFILES" rm file_to_remove
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully stopped tracking 1 item(s)" ]]
    [[ "$output" =~ "file_to_remove" ]]
    [[ "$output" =~ "Your local configs were not affected" ]]
    
    # Verify file is removed from backup
    [ ! -f "$BACKUP_DIR/files/file_to_remove" ]
    
    # Verify file still exists in HOME
    [ -f "$HOME/file_to_remove" ]
    
    # Verify commit and push (check log)
    cd "$BACKUP_DIR"
    run git log -1 --pretty=%s
    [[ "$output" =~ "Stop tracking file_to_remove" ]]
    
    # Verify remote has the commit
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git ls-remote origin main | awk '{print $1}')
    [ "$local_hash" = "$remote_hash" ]
}

@test "'dotfiles rm' successfully removes dir with files inside (HOME is not affected)" {
    init_backup_repo
    
    mkdir -p "$HOME/dir_to_remove"
    touch "$HOME/dir_to_remove/file1"
    run "$DOTFILES" add dir_to_remove
    [ "$status" -eq 0 ]
    
    run "$DOTFILES" rm dir_to_remove
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully stopped tracking 1 item(s)" ]]
    [[ "$output" =~ "dir_to_remove" ]]
    
    # Verify directory is removed from backup
    [ ! -d "$BACKUP_DIR/files/dir_to_remove" ]
    
    # Verify directory still exists in HOME
    [ -d "$HOME/dir_to_remove" ]
    [ -f "$HOME/dir_to_remove/file1" ]
}

@test "'dotfiles rm' successfully removes multiple files and dirs" {
    init_backup_repo
    
    touch "$HOME/file_a"
    mkdir -p "$HOME/dir_b"
    touch "$HOME/dir_b/file_b"
    
    run "$DOTFILES" add file_a dir_b
    [ "$status" -eq 0 ]
    
    run "$DOTFILES" rm file_a dir_b
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully stopped tracking 2 item(s)" ]]
    [[ "$output" =~ "- file_a" ]]
    [[ "$output" =~ "- dir_b" ]]
    
    # Verify both are removed from backup
    [ ! -f "$BACKUP_DIR/files/file_a" ]
    [ ! -d "$BACKUP_DIR/files/dir_b" ]
    
    # Verify both still exist in HOME
    [ -f "$HOME/file_a" ]
    [ -d "$HOME/dir_b" ]
    [ -f "$HOME/dir_b/file_b" ]
}
