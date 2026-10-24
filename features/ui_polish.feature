Feature: Consistent pages and helpful empty states
  So that HQ and store teams always know what a page is for and what to do next,
  every list page shares one header layout, one primary action and a clear empty state.

  Background:
    Given a Moroccan retail brand with an HQ user and a store user

  Scenario Outline: HQ list pages offer exactly one primary action in the header
    Given I am signed in as the HQ user
    When I open the "<page>" page
    Then the page header has exactly one primary action

    Examples:
      | page        |
      | visits      |
      | vm missions |
      | playbooks   |
      | briefs      |

  Scenario: An empty visits list explains itself and offers the next step
    Given I am signed in as the HQ user
    When I open the "visits" page
    Then I see an empty state saying "Aucune visite pour le moment."
    And the empty state offers the action "Planifier une visite"

  Scenario: An empty knowledge base offers to write the first article
    Given I am signed in as the HQ user
    When I open the "knowledge base" page
    Then I see an empty state saying "Aucun article pour le moment."
    And the empty state offers the action "Nouvel article"

  Scenario: A store user with no briefs sees an empty inbox without HQ actions
    Given I am signed in as the store user
    When I open the "inbox" page
    Then I see an empty state
    And the empty state offers no action

  Scenario: The reports store filter does not claim "no match" while rows are listed
    Given I am signed in as the HQ user
    When I open the "reports" page
    Then the "no match" message is hidden

  @javascript
  Scenario: The brief composer header is translated while the title is empty
    Given I am signed in as the HQ user
    When I open the brief composer
    Then the composer header reads "Brief sans titre"
