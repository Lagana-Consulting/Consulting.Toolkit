@{
  Severity = @('Error','Warning')

  # Keep the module strict, but don't fail CI on "runner-style" script patterns
  ExcludePath = @(
    'src\client.scripts\**'
  )

  # Optional: add exclusions only if they become noisy
  ExcludeRules = @(
    # 'PSAvoidUsingWriteHost',
    # 'PSUseShouldProcessForStateChangingFunctions'
  )
}

