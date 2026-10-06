@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive tool: colored host output is intentional
        'PSAvoidUsingWriteHost'
    )
}
