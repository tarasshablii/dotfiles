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

@test "'dotfiles status' fails when backup repository does not exist" {
    # Ensure no backup dir exists
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" status
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles status' warns when remote is ahead of local" {
    init_backup_repo

    # Update remote with a new commit
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    run "$DOTFILES" status
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
    [[ "$output" =~ "Please, run 'dotfiles pull' to update" ]]
}

@test "'dotfiles status' warns when local is ahead of remote" {
    init_backup_repo

    # Make a local change and commit it
    touch "$HOME/local_file"
    run "$DOTFILES" add local_file
    [ "$status" -eq 0 ]
    # 'add' pushes by default, so we need to reset remote to make local look "ahead" 
    # OR prevent push. But 'add' pushes.
    # Easier way: make a commit manually in BACKUP_DIR without pushing
    
    cd "$BACKUP_DIR"
    touch "manual_file"
    git add manual_file
    git commit -m "Manual local commit" > /dev/null
    cd - > /dev/null

    run "$DOTFILES" status
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Your local backup is ahead of remote" ]]
}

@test "'dotfiles status' shows correct profile, counts, and drift details" {
    init_backup_repo
    
    # 1. Setup files
    touch "$HOME/file_sync"
    touch "$HOME/file_modified"
    touch "$HOME/file_missing"
    
    # 2. Track them
    run "$DOTFILES" add file_sync file_modified file_missing
    [ "$status" -eq 0 ]
    
    # 3. Modify state to create drift
    echo "changed" > "$HOME/file_modified"
    rm "$HOME/file_missing"
    
    # 4. Run status
    run "$DOTFILES" status
    
    [ "$status" -eq 0 ]
    
    # General Info
    [[ "$output" =~ "Current Profile: main" ]]
    [[ "$output" =~ "Tracked Files: 3" ]]
    [[ "$output" =~ "Latest Change:" ]]
    
    # Drift Section
    [[ "$output" =~ "--- Dotfiles Drift ---" ]]
    
    # Check specific file statuses
    # We use grep because the output order might vary or exact line matching is tricky with arrays
    echo "$output" | grep "✅ file_sync (in sync)"
    echo "$output" | grep "⚠️ file_modified (modified"
    echo "$output" | grep "❌ file_missing (missing"
}
