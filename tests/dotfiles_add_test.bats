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

@test "'dotfiles add' fails when backup repository does not exist" {
    # Ensure no backup dir exists
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" add some_file
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles add' fails when local backup is behind remote" {
    init_backup_repo

    # Update remote with a new commit
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    # Create a file in HOME to attempt to add
    touch "$HOME/test_file"

    run "$DOTFILES" add test_file
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
    [[ "$output" =~ "Please, run 'dotfiles pull' to update" ]]
}

@test "'dotfiles add' aborts when current branch does not match profile" {
    init_backup_repo
    
    # Switch to a different branch in backup
    cd "$BACKUP_DIR"
    git checkout -b dev > /dev/null
    # .current_profile is still "main" from init_backup_repo
    cd - > /dev/null

    # Create a file in HOME to attempt to add
    touch "$HOME/test_file"

    run sh -c "echo n | $DOTFILES add test_file"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "You are on branch 'dev', but the last applied profile was 'main'" ]]
    [[ "$output" =~ "Aborting" ]]
}

@test "'dotfiles add' reports error for non-existent file" {
    init_backup_repo
    
    run "$DOTFILES" add non_existent_file
    
    # Expect status 0, but error message in output
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Could not add" ]]
    [[ "$output" =~ "non_existent_file': File does not exist." ]]
}

@test "'dotfiles add' reports error for file not under HOME directory" {
    init_backup_repo
    
    # Create file in the temp dir (parent of HOME)
    touch "$TEST_TEMP_DIR/outside_home_file"
    
    # Use relative path traversing up from HOME
    run "$DOTFILES" add "../outside_home_file"
    
    # Expect status 0, but error message in output
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Could not add" ]]
    [[ "$output" =~ "Path is not inside the home directory." ]]
}

@test "'dotfiles add' reports error for already tracked file" {
    init_backup_repo
    
    # Create and successfully add a file first
    touch "$HOME/already_tracked_file"
    run "$DOTFILES" add already_tracked_file
    [ "$status" -eq 0 ] # Ensure first add was successful

    # Attempt to add the same file again
    run "$DOTFILES" add already_tracked_file
    
    # Expect status 0, but error message in output
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Could not add" ]]
    [[ "$output" =~ "already_tracked_file': Already tracked." ]]
}

@test "'dotfiles add' successfully tracks a new file" {
    init_backup_repo
    
    touch "$HOME/new_file"
    echo "content" > "$HOME/new_file"
    
    run "$DOTFILES" add new_file
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully started tracking 1 item(s)" ]]
    [[ "$output" =~ "new_file" ]]
    
    # Verify file is in backup
    [ -f "$BACKUP_DIR/files/new_file" ]
    run cat "$BACKUP_DIR/files/new_file"
    [ "$output" = "content" ]
    
    # Verify commit and push (check log)
    cd "$BACKUP_DIR"
    run git log -1 --pretty=%s
    [[ "$output" =~ "Start tracking new_file" ]]
    
    # Verify remote has the commit
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git ls-remote origin main | awk '{print $1}')
    [ "$local_hash" = "$remote_hash" ]
}

@test "'dotfiles add' successfully tracks a directory with files" {
    init_backup_repo
    
    mkdir -p "$HOME/config_dir"
    touch "$HOME/config_dir/file1"
    echo "data2" > "$HOME/config_dir/file2"
    
    run "$DOTFILES" add config_dir
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully started tracking 1 item(s)" ]]
    [[ "$output" =~ "config_dir" ]]
    
    # Verify directory structure in backup
    [ -d "$BACKUP_DIR/files/config_dir" ]
    [ -f "$BACKUP_DIR/files/config_dir/file1" ]
    [ -f "$BACKUP_DIR/files/config_dir/file2" ]
    run cat "$BACKUP_DIR/files/config_dir/file2"
    [ "$output" = "data2" ]
}

@test "'dotfiles add' successfully tracks multiple files and dirs" {
    init_backup_repo
    
    touch "$HOME/file_a"
    mkdir -p "$HOME/dir_b"
    touch "$HOME/dir_b/file_b"
    
    run "$DOTFILES" add file_a dir_b
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully started tracking 2 item(s)" ]]
    [[ "$output" =~ "- file_a" ]]
    [[ "$output" =~ "- dir_b" ]]
    
    # Verify both exist in backup
    [ -f "$BACKUP_DIR/files/file_a" ]
    [ -d "$BACKUP_DIR/files/dir_b" ]
    [ -f "$BACKUP_DIR/files/dir_b/file_b" ]
}
