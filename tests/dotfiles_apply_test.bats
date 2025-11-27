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

@test "'dotfiles apply' fails when backup repository does not exist" {
    run "$DOTFILES" apply
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles apply' fails when local backup is behind remote" {
    init_backup_repo
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    run "$DOTFILES" apply
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
}

@test "'dotfiles apply' aborts when current branch does not match profile" {
    init_backup_repo
    cd "$BACKUP_DIR"
    git checkout -b dev > /dev/null
    cd - > /dev/null

    run sh -c "echo n | $DOTFILES apply"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "You are on branch 'dev', but the last applied profile was 'main'" ]]
}

@test "'dotfiles apply' reports no tracked files when backup has no 'files/'" {
    init_backup_repo
    
    run "$DOTFILES" apply
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No dotfiles are tracked" ]]
}

@test "'dotfiles apply' reports success when all files are in sync" {
    init_backup_repo
    
    # Add a file to backup
    cd "$BACKUP_DIR"
    mkdir -p files
    echo "content" > files/testrc
    git add files/testrc
    git commit -m "Add testrc" > /dev/null
    cd - > /dev/null

    # Create identical file in HOME
    echo "content" > "$HOME/testrc"

    run "$DOTFILES" apply
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "All dotfiles are in sync" ]]
}

@test "'dotfiles apply' copies new files from backup to home" {
    init_backup_repo
    
    # Add a new file to backup
    cd "$BACKUP_DIR"
    mkdir -p files
    echo "new content" > files/newrc
    git add files/newrc
    git commit -m "Add newrc" > /dev/null
    cd - > /dev/null

    run "$DOTFILES" apply
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "New files to be copied" ]]
    [[ "$output" =~ "Copied: newrc" ]]
    
    [ -f "$HOME/newrc" ]
    run cat "$HOME/newrc"
    [ "$output" = "new content" ]
}

@test "'dotfiles apply' skips conflicts when user chooses skip" {
    init_backup_repo
    
    # Add a conflicting file
    cd "$BACKUP_DIR"
    mkdir -p files
    echo "backup content" > files/conflictrc
    git add files/conflictrc
    git commit -m "Add conflictrc" > /dev/null
    cd - > /dev/null

    # Create different file in HOME
    echo "home content" > "$HOME/conflictrc"

    # Run apply with 's' (skip)
    run sh -c "echo s | $DOTFILES apply"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Conflicting files found" ]]
    [[ "$output" =~ "Skipping" ]]
    
    # Verify content is unchanged
    run cat "$HOME/conflictrc"
    [ "$output" = "home content" ]
}

@test "'dotfiles apply' overwrites conflicts when user chooses overwrite" {
    init_backup_repo
    
    # Add a conflicting file
    cd "$BACKUP_DIR"
    mkdir -p files
    echo "backup content" > files/conflictrc
    git add files/conflictrc
    git commit -m "Add conflictrc" > /dev/null
    cd - > /dev/null

    # Create different file in HOME
    echo "home content" > "$HOME/conflictrc"

    # Run apply with 'o' (overwrite)
    run sh -c "echo o | $DOTFILES apply"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Conflicting files found" ]]
    [[ "$output" =~ "Overwriting" ]]
    [[ "$output" =~ "Overwritten: conflictrc" ]]
    
    # Verify content is updated
    run cat "$HOME/conflictrc"
    [ "$output" = "backup content" ]
}
