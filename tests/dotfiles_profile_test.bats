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

@test "'dotfiles profile' fails when backup repository does not exist" {
    rm -rf "$BACKUP_DIR"

    run "$DOTFILES" profile
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Backup repository not initialized" ]]
}

@test "'dotfiles profile' lists available profiles and highlights current" {
    init_backup_repo
    
    # Create another profile (branch)
    cd "$BACKUP_DIR"
    git branch work
    cd - > /dev/null
    
    run "$DOTFILES" profile
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Available profiles (branches):" ]]
    [[ "$output" =~ "main (current)" ]]
    [[ "$output" =~ "work" ]]
}

@test "'dotfiles profile' fails to switch when local backup is behind remote" {
    init_backup_repo

    # Update remote with a new commit
    local source_repo="$TEST_TEMP_DIR/source"
    cd "$source_repo"
    touch new_file
    git add new_file
    git commit -m "Remote change" > /dev/null
    git push > /dev/null
    cd - > /dev/null

    run "$DOTFILES" profile new_profile
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Your local backup is behind the remote" ]]
    [[ "$output" =~ "Please, run 'dotfiles pull' to update" ]]
}

@test "'dotfiles profile' aborts switch when drift is detected and user declines" {
    init_backup_repo
    
    # Create drift
    touch "$HOME/drift_file"
    run "$DOTFILES" add drift_file
    [ "$status" -eq 0 ]
    
    echo "changed" > "$HOME/drift_file"
    
    run sh -c "echo n | $DOTFILES profile new_profile"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Inconsistencies detected between your Home directory and the backup." ]]
    [[ "$output" =~ "Aborting profile switch." ]]
}

@test "'dotfiles profile' successfully switches to an existing profile" {
    init_backup_repo
    
    cd "$BACKUP_DIR"
    git branch work
    cd - > /dev/null
    
    run "$DOTFILES" profile work
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully switched to profile 'work'." ]]
    
    # Verify branch switch
    cd "$BACKUP_DIR"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$current_branch" = "work" ]
    
    # Verify .current_profile
    local profile_content=$(cat .current_profile)
    [ "$profile_content" = "work" ]
}

@test "'dotfiles profile' aborts creation of new profile if user declines" {
    init_backup_repo
    
    run sh -c "echo n | $DOTFILES profile new_profile"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Profile 'new_profile' does not exist locally." ]]
    [[ "$output" =~ "Do you want to create a new profile 'new_profile'?" ]]
    [[ "$output" =~ "Aborting profile creation." ]]
}

@test "'dotfiles profile' successfully creates and switches to a new profile with fresh state" {
    init_backup_repo
    
    # Create a file in the current profile 'main'
    touch "$HOME/file_main"
    run "$DOTFILES" add file_main
    [ "$status" -eq 0 ]
    
    # Switch to new profile
    run sh -c "echo y | $DOTFILES profile new_profile"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Creating and switching to new profile 'new_profile'..." ]]
    [[ "$output" =~ "Successfully created and switched to profile 'new_profile'." ]]
    
    # Verify branch switch
    cd "$BACKUP_DIR"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$current_branch" = "new_profile" ]
    
    # Verify .current_profile
    local profile_content=$(cat .current_profile)
    [ "$profile_content" = "new_profile" ]
    
    # Verify 'file_main' from previous profile is NOT in the new profile
    [ ! -f "files/file_main" ]
    
    # Verify remote branch exists
    local remote_branch=$(git ls-remote origin new_profile)
    [ -n "$remote_branch" ]
}
