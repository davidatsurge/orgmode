local helpers = require('tests.plenary.ui.helpers')
local api = require('orgmode.api')

describe('Api', function()
  it('should parse current file through api', function()
    local file = helpers.load_file_content({
      '#TITLE: First file',
      '',
      '* TODO Test orgmode :WORK:OFFICE:',
      '  DEADLINE: <2021-07-21 Wed 22:02>',
      '** TODO Second level :NESTEDTAG:',
      '  DEADLINE: <2021-07-21 Wed 22:02>',
      '* DONE Some task',
      '  DEADLINE: <2021-07-21 Wed 22:02>',
    })

    assert.are.same(3, #api.load())
    local current_file = api.current()
    assert.are.same(false, current_file.is_archive_file)
    assert.are.same(file, current_file.filename)
    assert.are.same(current_file.category, vim.fn.fnamemodify(file, ':p:t:r'))
    assert.are.same(3, #current_file.headlines)
    assert.are.same('Test orgmode', current_file.headlines[1].title)
    assert.are.same({ 'WORK', 'OFFICE' }, current_file.headlines[1].tags)
    assert.are.same({ 'WORK', 'OFFICE' }, current_file.headlines[1].own_tags)
    assert.are.same(1, #current_file.headlines[1].headlines)
    assert.are.same('TODO', current_file.headlines[1].todo_value)
    assert.are.same('TODO', current_file.headlines[1].todo_type)
    assert.are.same(3, current_file.headlines[1].position.start_line)
    assert.are.same(1, current_file.headlines[1].position.start_col)
    assert.are.same(6, current_file.headlines[1].position.end_line)
    assert.are.same(0, current_file.headlines[1].position.end_col)
    assert.is.Nil(current_file.headlines[1].parent)

    assert.are.same('Second level', current_file.headlines[2].title)
    assert.are.same(0, #current_file.headlines[2].headlines)
    assert.are.same({ 'WORK', 'OFFICE', 'NESTEDTAG' }, current_file.headlines[2].tags)
    assert.are.same({ 'NESTEDTAG' }, current_file.headlines[2].own_tags)
    assert.are.same('TODO', current_file.headlines[2].todo_value)
    assert.are.same('TODO', current_file.headlines[2].todo_type)
    assert.are.same(5, current_file.headlines[2].position.start_line)
    assert.are.same(1, current_file.headlines[2].position.start_col)
    assert.are.same(6, current_file.headlines[2].position.end_line)
    assert.are.same(0, current_file.headlines[2].position.end_col)
    assert.are.same(current_file.headlines[1], current_file.headlines[2].parent)

    assert.are.same('Some task', current_file.headlines[3].title)
    assert.are.same(0, #current_file.headlines[3].headlines)
    assert.are.same({}, current_file.headlines[3].tags)
    assert.are.same({}, current_file.headlines[3].own_tags)
    assert.are.same('DONE', current_file.headlines[3].todo_value)
    assert.are.same('DONE', current_file.headlines[3].todo_type)
    assert.are.same(7, current_file.headlines[3].position.start_line)
    assert.are.same(1, current_file.headlines[3].position.start_col)
    assert.are.same(8, current_file.headlines[3].position.end_line)
    assert.are.same(34, current_file.headlines[3].position.end_col)
    assert.is.Nil(current_file.headlines[3].parent)
  end)
end)
