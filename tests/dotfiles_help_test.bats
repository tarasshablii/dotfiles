#!/usr/bin/env bats

setup() {
    # Define the path to the dotfiles script relative to the test directory
    DOTFILES="$BATS_TEST_DIRNAME/../dotfiles"
}

@test "'dotfiles help' displays usage information" {
    run "$DOTFILES" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: dotfiles <command> [options]" ]]
    [[ "$output" =~ "Commands:" ]]
    [[ "$output" =~ "  init" ]]
    [[ "$output" =~ "  install" ]]
    [[ "$output" =~ "  apply" ]]
    [[ "$output" =~ "  add" ]]
    [[ "$output" =~ "  rm" ]]
    [[ "$output" =~ "  backup" ]]
    [[ "$output" =~ "  status" ]]
    [[ "$output" =~ "  diff" ]]
    [[ "$output" =~ "  profile" ]]
    [[ "$output" =~ "  pull" ]]
    [[ "$output" =~ "  update" ]]
    [[ "$output" =~ "  uninstall" ]]
    [[ "$output" =~ "  help" ]]
}
