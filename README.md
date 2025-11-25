```markdown
# ZabbixApi PowerShell Module (Zabbix 7.4) — Enhanced

This module is an enhanced PowerShell wrapper for the Zabbix 7.4 JSON-RPC API.

Enhancements in this version:
- Resolve-ZabbixGroupId / Resolve-ZabbixTemplateId helpers (name → id)
- User management: Get/New/Set/Remove users
- Action management: Get/New/Remove actions
- Maintenance management: Get/New/Remove maintenance windows
- Discovery rules: Get/New/Remove discovery rules
- Pester tests and GitHub Actions workflow included to run tests on push/PR

Usage highlights:
- Resolve group names to ids:
  Resolve-ZabbixGroupId -Names 'Linux servers','Windows servers'

- Create a user (group ids are required):
  New-ZabbixUser -Alias 'ops' -Password 'Secret!' -Name 'Ops' -GroupIds @('2')

- Create an action:
  $action = @{
    name = 'Notify Ops'
    eventsource = 0
    status = 0
    esc_period = 120
    operations = @(
      @{
        operationtype = 0
        opmessage = @{ default_msg = 1; mediatypeid = '1' }
        opmessage_usr = @( @{ userid = '1' } )
      }
    )
    conditions = @(
      @{ conditiontype = 3; operator = 0; value = '1' } # host group condition example
    )
  }
  New-ZabbixAction -ActionObject $action

Testing & CI:
- Pester tests are included under Tests/
- GitHub Actions workflow: .github/workflows/pester.yml will run tests on Windows and macOS PowerShell-based runners

Notes:
- The module stores the auth token in a module-scoped variable.
- Many wrappers accept either numeric ids or names; use Resolve-* helpers when convenient.
- These functions are thin wrappers — they forward arguments to the Zabbix API. Validate payloads against Zabbix API docs when constructing complex objects.

```