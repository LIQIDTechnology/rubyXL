module RubyXL
  module WorkbookConvenienceMethods
    SHEET_NAME_TEMPLATE = 'Sheet%d'

    # Finds worksheet by its name or numerical index
    def [](ind)
      case ind
      when Integer then worksheets[ind]
      when String  then worksheets.find { |ws| ws.sheet_name == ind }
      end
    end

    # Create new simple worksheet and add it to the workbook worksheets
    #
    # @param [String] The name for the new worksheet
    def add_worksheet(name = nil)
      if name.nil? then
        n = 0

        begin
          name = SHEET_NAME_TEMPLATE % (n += 1)
        end until self[name].nil?
      end

      new_worksheet = Worksheet.new(:workbook => self, :sheet_name => name)
      worksheets << new_worksheet
      new_worksheet
    end

    def each
      worksheets.each{ |i| yield i }
    end

    def date1904
      workbook_properties && workbook_properties.date1904
    end

    def date1904=(v)
      self.workbook_properties ||= RubyXL::WorkbookProperties.new
      workbook_properties.date1904 = v
    end

    def company
      root.document_properties.company && root.document_properties.company.value
    end

    def company=(v)
      root.document_properties.company ||= StringNode.new
      root.document_properties.company.value = v
    end

    def application
      root.document_properties.application && root.document_properties.application.value
    end

    def application=(v)
      root.document_properties.application ||= StringNode.new
      root.document_properties.application.value = v
    end

    def appversion
      root.document_properties.app_version && root.document_properties.app_version.value
    end

    def appversion=(v)
      root.document_properties.app_version ||= StringNode.new
      root.document_properties.app_version.value = v
    end

    def creator
      root.core_properties.creator
    end

    def creator=(v)
      root.core_properties.creator = v
    end

    def modifier
      root.core_properties.modifier
    end

    def modifier=(v)
      root.core_properties.modifier = v
    end

    def created_at
      root.core_properties.created_at
    end

    def created_at=(v)
      root.core_properties.created_at = v
    end

    def modified_at
      root.core_properties.modified_at
    end

    def modified_at=(v)
      root.core_properties.modified_at = v
    end

    def cell_xfs # Stylesheet should be pre-filled with defaults on initialize()
      stylesheet.cell_xfs
    end

    def fonts # Stylesheet should be pre-filled with defaults on initialize()
      stylesheet.fonts
    end

    def fills # Stylesheet should be pre-filled with defaults on initialize()
      stylesheet.fills
    end

    def borders # Stylesheet should be pre-filled with defaults on initialize()
      stylesheet.borders
    end

    def get_fill_color(xf)
      fill = fills[xf.fill_id]
      pattern = fill && fill.pattern_fill
      color = pattern && pattern.fg_color
      color && color.rgb || 'ffffff'
    end

    def register_new_fill(new_fill, old_xf)
      new_xf = old_xf.dup
      new_xf.apply_fill = true
      new_xf.fill_id = fills.find_index { |x| x == new_fill } # Use existing fill, if it exists
      new_xf.fill_id ||= fills.size # If this fill has never existed before, add it to collection.
      fills[new_xf.fill_id] = new_fill
      new_xf
    end

    def register_new_font(new_font, old_xf)
      new_xf = old_xf.dup
      new_xf.apply_font = true
      new_xf.font_id = fonts.find_index { |x| x == new_font } # Use existing font, if it exists
      new_xf.font_id ||= fonts.size # If this font has never existed before, add it to collection.
      fonts[new_xf.font_id] = new_font
      new_xf
    end

    def register_new_xf(new_xf)
      new_xf_id = cell_xfs.find_index { |xf| xf == new_xf } # Use existing XF, if it exists
      new_xf_id ||= cell_xfs.size # If this XF has never existed before, add it to collection.
      cell_xfs[new_xf_id] = new_xf
      new_xf_id
    end

    def modify_alignment(style_index, &block)
      xf = cell_xfs[style_index].dup
      xf.alignment ||= RubyXL::Alignment.new
      xf.apply_alignment = true
      yield(xf.alignment)
      register_new_xf(xf)
    end

    def modify_fill(style_index, rgb)
      xf = cell_xfs[style_index].dup
      new_fill = RubyXL::Fill.new(:pattern_fill =>
                   RubyXL::PatternFill.new(:pattern_type => 'solid',
                                           :fg_color => RubyXL::Color.new(:rgb => rgb)))
      new_xf = register_new_fill(new_fill, xf)
      register_new_xf(new_xf)
    end

    def modify_border(style_index, direction, weight)
      old_xf = cell_xfs[style_index].dup
      new_border = borders[old_xf.border_id].dup
      new_border.set_edge_style(direction, weight)

      new_xf = old_xf.dup
      new_xf.apply_border = true

      new_xf.border_id = borders.find_index { |x| x == new_border } # Use existing border, if it exists
      new_xf.border_id ||= borders.size # If this border has never existed before, add it to collection.
      borders[new_xf.border_id] = new_border

      register_new_xf(new_xf)
    end

  end


  module WorksheetConvenienceMethods
    NAME = 0
    SIZE = 1
    COLOR = 2
    ITALICS = 3
    BOLD = 4
    UNDERLINE = 5
    STRIKETHROUGH = 6

    def insert_cell(row = 0, col = 0, data = nil, formula = nil, shift = nil)
      validate_workbook
      ensure_cell_exists(row, col)

      case shift
      when nil then # No shifting at all
      when :right then
        sheet_data.rows[row].insert_cell_shift_right(nil, col)
      when :down then
        add_row(sheet_data.size, :cells => Array.new(sheet_data.rows[row].size))
        (sheet_data.size - 1).downto(row+1) { |index|
          sheet_data.rows[index].cells[col] = sheet_data.rows[index-1].cells[col]
        }
      else
        raise 'invalid shift option'
      end

      return add_cell(row,col,data,formula)
    end

    # by default, only sets cell to nil
    # if :left is specified, method will shift row contents to the right of the deleted cell to the left
    # if :up is specified, method will shift column contents below the deleted cell upward
    def delete_cell(row_index = 0, column_index=0, shift=nil)
      validate_workbook
      validate_nonnegative(row_index)
      validate_nonnegative(column_index)

      row = sheet_data[row_index]
      old_cell = row && row[column_index]

      case shift
      when nil then
        row.cells[column_index] = nil if row
      when :left then
        row.delete_cell_shift_left(column_index) if row
      when :up then
        (row_index...(sheet_data.size - 1)).each { |index|
          c = sheet_data.rows[index].cells[column_index] = sheet_data.rows[index + 1].cells[column_index]
          c.row -= 1 if c.is_a?(Cell)
        }
      else
        raise 'invalid shift option'
      end

      return old_cell
    end

    # Inserts row at row_index, pushes down, copies style from the row above (that's what Excel 2013 does!)
    # NOTE: use of this method will break formulas which reference cells which are being "pushed down"
    def insert_row(row_index = 0)
      validate_workbook
      ensure_cell_exists(row_index)

      old_row = new_cells = nil

      if row_index > 0 then
        old_row = sheet_data.rows[row_index - 1]
        if old_row then
          new_cells = old_row.cells.collect { |c|
                        if c.nil? then nil
                        else nc = RubyXL::Cell.new(:style_index => c.style_index)
                             nc.worksheet = self
                             nc
                        end
                      }
        end
      end

      row0 = sheet_data.rows[0]
      new_cells ||= Array.new((row0 && row0.cells.size) || 0)

      sheet_data.rows.insert(row_index, nil)
      new_row = add_row(row_index, :cells => new_cells, :style_index => old_row && old_row.style_index)

      # Update row values for all rows below
      row_index.upto(sheet_data.rows.size - 1) { |i|
        row = sheet_data.rows[i]
        next if row.nil?
        row.cells.each { |c| c.row = i unless c.nil? }
      }

      return new_row
    end

    def delete_row(row_index=0)
      validate_workbook
      validate_nonnegative(row_index)

      deleted = sheet_data.rows.delete_at(row_index)

      # Update row number of each cell
      row_index.upto(sheet_data.size - 1) { |index|
        row = sheet_data[index]
        row && row.cells.each{ |c| c.row -= 1 unless c.nil? }
      }

      return deleted
    end

    # Inserts column at +column_index+, pushes everything right, takes styles from column to left
    # NOTE: use of this method will break formulas which reference cells which are being "pushed right"
    def insert_column(column_index = 0)
      validate_workbook
      ensure_cell_exists(0, column_index)

      old_range = cols.get_range(column_index)

      #go through each cell in column
      sheet_data.rows.each_with_index { |row, row_index|
        old_cell = row[column_index]
        c = nil

        if old_cell && old_cell.style_index != 0 &&
             old_range && old_range.style_index != old_cell.style_index then

          c = RubyXL::Cell.new(:style_index => old_cell.style_index, :worksheet => self,
                               :row => row_index, :column => column_index,
                               :datatype => RubyXL::DataType::SHARED_STRING)
        end

        row.insert_cell_shift_right(c, column_index)
      }

      cols.insert_column(column_index)

      # TODO: update column numbers
    end

    def delete_column(column_index = 0)
      validate_workbook
      validate_nonnegative(column_index)

      #delete column
      sheet_data.rows.each { |row| row.cells.delete_at(column_index) }

      # Change column numbers for cells to the right of the deleted column
      sheet_data.rows.each_with_index { |row, row_index|
        row.cells.each_with_index { |c, column_index|
          c.column = column_index if c.is_a?(Cell)
        }
      }

      cols.each { |range| range.delete_column(column_index) }
    end

    def get_row_style(row_index)
      row = sheet_data.rows[row_index]
      (row && row.style_index) || 0
    end

    def get_row_fill(row = 0)
      (row = sheet_data.rows[row]) && row.get_fill_color
    end

    def get_row_font_name(row = 0)
      (font = row_font(row)) && font.get_name
    end

    def get_row_font_size(row = 0)
      (font = row_font(row)) && font.get_size
    end

    def get_row_font_color(row = 0)
      font = row_font(row)
      color = font && font.color
      color && (color.rgb || '000000')
    end

    def is_row_italicized(row = 0)
      (font = row_font(row)) && font.is_italic
    end

    def is_row_bolded(row = 0)
      (font = row_font(row)) && font.is_bold
    end

    def is_row_underlined(row = 0)
      (font = row_font(row)) && font.is_underlined
    end

    def is_row_struckthrough(row = 0)
      (font = row_font(row)) && font.is_strikethrough
    end

    def get_row_height(row = 0)
      validate_workbook
      validate_nonnegative(row)
      row = sheet_data.rows[row]
      row && row.ht || 13
    end

    def get_row_border(row, border_direction)
      validate_workbook

      border = @workbook.borders[get_row_xf(row).border_id]
      border && border.get_edge_style(border_direction)
    end

    def row_font(row)
      (row = sheet_data.rows[row]) && row.get_font
    end

    def get_row_alignment(row, is_horizontal)
      validate_workbook

      xf_obj = get_row_xf(row)
      return nil if xf_obj.alignment.nil?

      if is_horizontal then return xf_obj.alignment.horizontal
      else                  return xf_obj.alignment.vertical
      end
    end

    def get_row_horizontal_alignment(row = 0)
      warn "[DEPRECATION] `#{__method__}` is deprecated.  Please use `get_row_alignment` instead."
      return get_row_alignment(row, true)
    end

    def get_row_vertical_alignment(row = 0)
      warn "[DEPRECATION] `#{__method__}` is deprecated.  Please use `get_row_alignment` instead."
      return get_row_alignment(row, false)
    end

    def get_cols_style_index(column_index)
      validate_nonnegative(column_index)
      range = cols.locate_range(column_index)
      (range && range.style_index) || 0
    end

    def get_column_font_name(col = 0)
      font = column_font(col)
      font && font.get_name
    end

    def get_column_font_size(col = 0)
      font = column_font(col)
      font && font.get_size
    end

    def get_column_font_color(col = 0)
      font = column_font(col)
      font && (font.get_rgb_color || '000000')
    end

    def is_column_italicized(col = 0)
      font = column_font(col)
      font && font.is_italic
    end

    def is_column_bolded(col = 0)
      font = column_font(col)
      font && font.is_bold
    end

    def is_column_underlined(col = 0)
      font = column_font(col)
      font && font.is_underlined
    end

    def is_column_struckthrough(col = 0)
      font = column_font(col)
      font && font.is_strikethrough
    end

    # Get raw column width value as stored in the file
    def get_column_width_raw(column_index = 0)
      validate_workbook
      validate_nonnegative(column_index)

      range = cols.locate_range(column_index)
      range && range.width
    end

    # Get column width measured in number of digits, as per
    # http://msdn.microsoft.com/en-us/library/documentformat.openxml.spreadsheet.column%28v=office.14%29.aspx
    def get_column_width(column_index = 0)
      width = get_column_width_raw(column_index)
      return RubyXL::ColumnRange::DEFAULT_WIDTH if width.nil?
      (width - (5.0 / RubyXL::Font::MAX_DIGIT_WIDTH)).round
    end

    # Helper method to get the style index for a column
    def get_col_style(column_index)
      range = cols.locate_range(column_index)
      (range && range.style_index) || 0
    end

    def get_column_fill(col=0)
      validate_workbook
      validate_nonnegative(col)

      @workbook.get_fill_color(get_col_xf(col))
    end

    def get_column_border(col, border_direction)
      validate_workbook

      xf = @workbook.cell_xfs[get_cols_style_index(col)]
      border = @workbook.borders[xf.border_id]
      border && border.get_edge_style(border_direction)
    end

    def column_font(col)
      validate_workbook

      @workbook.fonts[@workbook.cell_xfs[get_cols_style_index(col)].font_id]
    end

    def get_column_alignment(col, type)
      validate_workbook

      xf = @workbook.cell_xfs[get_cols_style_index(col)]
      xf.alignment && xf.alignment.send(type)
    end

    def change_row_horizontal_alignment(row = 0, alignment = 'center')
      validate_workbook
      validate_nonnegative(row)
      change_row_alignment(row) { |a| a.horizontal = alignment }
    end

    def change_row_vertical_alignment(row = 0, alignment = 'center')
      validate_workbook
      validate_nonnegative(row)
      change_row_alignment(row) { |a| a.vertical = alignment }
    end

    def change_row_border(row, direction, weight)
      validate_workbook
      ensure_cell_exists(row)

      sheet_data.rows[row].style_index = @workbook.modify_border(get_row_style(row), direction, weight)

      sheet_data[row].cells.each { |c|
        c.change_border(direction, weight) unless c.nil?
      }
    end

    def change_row_fill(row_index = 0, rgb = 'ffffff')
      validate_workbook
      ensure_cell_exists(row_index)
      Color.validate_color(rgb)

      sheet_data.rows[row_index].style_index = @workbook.modify_fill(get_row_style(row_index), rgb)
      sheet_data[row_index].cells.each { |c| c.change_fill(rgb) unless c.nil? }
    end

    # Helper method to update the row styles array
    # change_type - NAME or SIZE or COLOR etc
    # main method to change font, called from each separate font mutator method
    def change_row_font(row_index, change_type, arg, font)
      validate_workbook
      ensure_cell_exists(row_index)

      xf = workbook.register_new_font(font, get_row_xf(row_index))
      row = sheet_data[row_index]
      row.style_index = workbook.register_new_xf(xf)
      row.cells.each { |c| c.font_switch(change_type, arg) unless c.nil? }
    end

    def change_row_font_name(row = 0, font_name = 'Verdana')
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_name(font_name)
      change_row_font(row, Worksheet::NAME, font_name, font)
    end

    def change_row_font_size(row = 0, font_size=10)
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_size(font_size)
      change_row_font(row, Worksheet::SIZE, font_size, font)
    end

    def change_row_font_color(row = 0, font_color = '000000')
      ensure_cell_exists(row)
      Color.validate_color(font_color)
      font = row_font(row).dup
      font.set_rgb_color(font_color)
      change_row_font(row, Worksheet::COLOR, font_color, font)
    end

    def change_row_italics(row = 0, italicized = false)
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_italic(italicized)
      change_row_font(row, Worksheet::ITALICS, italicized, font)
    end

    def change_row_bold(row = 0, bolded = false)
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_bold(bolded)
      change_row_font(row, Worksheet::BOLD, bolded, font)
    end

    def change_row_underline(row = 0, underlined=false)
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_underline(underlined)
      change_row_font(row, Worksheet::UNDERLINE, underlined, font)
    end

    def change_row_strikethrough(row = 0, struckthrough=false)
      ensure_cell_exists(row)
      font = row_font(row).dup
      font.set_strikethrough(struckthrough)
      change_row_font(row, Worksheet::STRIKETHROUGH, struckthrough, font)
    end

    def change_row_height(row = 0, height = 10)
      validate_workbook
      ensure_cell_exists(row)

      c = sheet_data.rows[row]
      c.ht = height
      c.custom_height = true
    end

    # Helper method to update the fonts and cell styles array
    # main method to change font, called from each separate font mutator method
    def change_column_font(column_index, change_type, arg, font, xf)
      validate_workbook
      ensure_cell_exists(0, column_index)

      xf = workbook.register_new_font(font, xf)
      cols.get_range(column_index).style_index = workbook.register_new_xf(xf)

      sheet_data.rows.each { |row|
        c = row && row[column_index]
        c.font_switch(change_type, arg) unless c.nil?
      }
    end

    def change_column_font_name(column_index = 0, font_name = 'Verdana')
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_name(font_name)
      change_column_font(column_index, Worksheet::NAME, font_name, font, xf)
    end

    def change_column_font_size(column_index, font_size=10)
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_size(font_size)
      change_column_font(column_index, Worksheet::SIZE, font_size, font, xf)
    end

    def change_column_font_color(column_index, font_color='000000')
      Color.validate_color(font_color)

      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_rgb_color(font_color)
      change_column_font(column_index, Worksheet::COLOR, font_color, font, xf)
    end

    def change_column_italics(column_index, italicized = false)
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_italic(italicized)
      change_column_font(column_index, Worksheet::ITALICS, italicized, font, xf)
    end

    def change_column_bold(column_index, bolded = false)
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_bold(bolded)
      change_column_font(column_index, Worksheet::BOLD, bolded, font, xf)
    end

    def change_column_underline(column_index, underlined = false)
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_underline(underlined)
      change_column_font(column_index, Worksheet::UNDERLINE, underlined, font, xf)
    end

    def change_column_strikethrough(column_index, struckthrough=false)
      xf = get_col_xf(column_index)
      font = @workbook.fonts[xf.font_id].dup
      font.set_strikethrough(struckthrough)
      change_column_font(column_index, Worksheet::STRIKETHROUGH, struckthrough, font, xf)
    end

    def change_column_horizontal_alignment(column_index, alignment = 'center')
      change_column_alignment(column_index) { |a| a.horizontal = alignment }
    end

    def change_column_vertical_alignment(column_index, alignment = 'center')
      change_column_alignment(column_index) { |a| a.vertical = alignment }
    end

    def change_column_border(column_index, direction, weight)
      validate_workbook
      ensure_cell_exists(0, column_index)

      cols.get_range(column_index).style_index = @workbook.modify_border(get_col_style(column_index), direction, weight)

      sheet_data.rows.each { |row|
        c = row.cells[column_index]
        c.change_border(direction, weight) unless c.nil?
      }
    end

    def change_row_alignment(row, &block)
      validate_workbook
      validate_nonnegative(row)
      ensure_cell_exists(row)

      sheet_data.rows[row].style_index = @workbook.modify_alignment(get_row_style(row), &block)

      sheet_data[row].cells.each { |c|
        next if c.nil?
        c.style_index = @workbook.modify_alignment(c.style_index, &block)
      }
    end

    def change_column_alignment(column_index, &block)
      validate_workbook
      ensure_cell_exists(0, column_index)

      cols.get_range(column_index).style_index = @workbook.modify_alignment(get_col_style(column_index), &block)
      # Excel gets confused if width is not explicitly set for a column that had alignment changes
      change_column_width(column_index) if get_column_width_raw(column_index).nil?

      sheet_data.rows.each { |row|
        c = row[column_index]
        next if c.nil?
        c.style_index = @workbook.modify_alignment(c.style_index, &block)
      }
    end

    # Returns 2D array of just the cell values (without style or formula information)
    def extract_data(args = {})
      warn "[DEPRECATION] `#{__method__}` is deprecated.  Please access data directly by iterating through .sheet_data.rows"
      sheet_data.rows.map { |row|
        row.cells.map { |c| c && c.value(args) } unless row.nil?
      }
    end

    def get_table(headers = [], opts = {})
      warn "[DEPRECATION] `#{__method__}` is deprecated.  Please access data directly by iterating through .sheet_data.rows"
      validate_workbook

      headers = [headers] unless headers.is_a?(Array)
      row_num = find_first_row_with_content(headers)
      return nil if row_num.nil?

      table_hash = {}
      table_hash[:table] = []

      header_row = sheet_data[row_num]
      header_row.cells.each_with_index { |header_cell, index|
        break if index>0 && !opts[:last_header].nil? && !header_row[index-1].nil? && !header_row[index-1].value.nil? && header_row[index-1].value.to_s==opts[:last_header]
        next if header_cell.nil? || header_cell.value.nil?
        header = header_cell.value.to_s
        table_hash[:sorted_headers]||=[]
        table_hash[:sorted_headers] << header
        table_hash[header] = []

        original_row = row_num + 1
        current_row = original_row

        row = sheet_data.rows[current_row]
        cell = row && row.cells[index]

        # makes array of hashes in table_hash[:table]
        # as well as hash of arrays in table_hash[header]
        table_index = current_row - original_row
        cell_test = (!cell.nil? && !cell.value.nil?)

        while cell_test || (table_hash[:table][table_index] && !table_hash[:table][table_index].empty?)
          table_hash[header] << cell.value if cell_test
          table_index = current_row - original_row

          if cell_test then
            table_hash[:table][table_index] ||= {}
            table_hash[:table][table_index][header] = cell.value
          end

          current_row += 1
          if sheet_data.rows[current_row].nil? then
            cell = nil
          else
            cell = sheet_data.rows[current_row].cells[index]
          end
          cell_test = (!cell.nil? && !cell.value.nil?)
        end
      }

      return table_hash
    end

  end


  module CellConvenienceMethods

    def change_contents(data, formula_expression = nil)
      validate_worksheet

      if formula_expression then
        self.datatype = nil
        self.formula = RubyXL::Formula.new(:expression => formula_expression)
      else
        self.datatype = case data
                        when Date, Numeric then nil
                        else RubyXL::DataType::RAW_STRING
                        end
      end

      data = workbook.date_to_num(data) if data.is_a?(Date)

      self.raw_value = data
    end

    def get_border(direction)
      validate_worksheet
      get_cell_border.get_edge_style(direction)
    end

    def change_horizontal_alignment(alignment = 'center')
      validate_worksheet
      self.style_index = workbook.modify_alignment(self.style_index) { |a| a.horizontal = alignment }
    end

    def change_vertical_alignment(alignment = 'center')
      validate_worksheet
      self.style_index = workbook.modify_alignment(self.style_index) { |a| a.vertical = alignment }
    end

    def change_text_wrap(wrap = false)
      validate_worksheet
      self.style_index = workbook.modify_alignment(self.style_index) { |a| a.wrap_text = wrap }
    end

    def change_border(direction, weight)
      validate_worksheet
      self.style_index = workbook.modify_border(self.style_index, direction, weight)
    end

    def is_italicized()
      validate_worksheet
      get_cell_font.is_italic
    end

    def is_bolded()
      validate_worksheet
      get_cell_font.is_bold
    end

    def is_underlined()
      validate_worksheet
      get_cell_font.is_underlined
    end

    def is_struckthrough()
      validate_worksheet
      get_cell_font.is_strikethrough
    end

    def font_name()
      validate_worksheet
      get_cell_font.get_name
    end

    def font_size()
      validate_worksheet
      get_cell_font.get_size
    end

    def font_color()
      validate_worksheet
      get_cell_font.get_rgb_color || '000000'
    end

    def fill_color()
      validate_worksheet
      return workbook.get_fill_color(get_cell_xf)
    end

    def horizontal_alignment()
      validate_worksheet
      xf_obj = get_cell_xf
      return nil if xf_obj.alignment.nil?
      xf_obj.alignment.horizontal
    end

    def vertical_alignment()
      validate_worksheet
      xf_obj = get_cell_xf
      return nil if xf_obj.alignment.nil?
      xf_obj.alignment.vertical
    end

    def text_wrap()
      validate_worksheet
      xf_obj = get_cell_xf
      return nil if xf_obj.alignment.nil?
      xf_obj.alignment.wrap_text
    end

    def set_number_format(format_code)
      new_xf = get_cell_xf.dup
      new_xf.num_fmt_id = workbook.stylesheet.register_number_format(format_code)
      new_xf.apply_number_format = true
      self.style_index = workbook.register_new_xf(new_xf)
    end

    # Changes fill color of cell
    def change_fill(rgb = 'ffffff')
      validate_worksheet
      Color.validate_color(rgb)
      self.style_index = workbook.modify_fill(self.style_index, rgb)
    end

    # Changes font name of cell
    def change_font_name(new_font_name = 'Verdana')
      validate_worksheet

      font = get_cell_font.dup
      font.set_name(new_font_name)
      update_font_references(font)
    end

    # Changes font size of cell
    def change_font_size(font_size = 10)
      validate_worksheet
      raise 'Argument must be a number' unless font_size.is_a?(Integer) || font_size.is_a?(Float)

      font = get_cell_font.dup
      font.set_size(font_size)
      update_font_references(font)
    end

    # Changes font color of cell
    def change_font_color(font_color = '000000')
      validate_worksheet
      Color.validate_color(font_color)

      font = get_cell_font.dup
      font.set_rgb_color(font_color)
      update_font_references(font)
    end

    # Changes font italics settings of cell
    def change_font_italics(italicized = false)
      validate_worksheet

      font = get_cell_font.dup
      font.set_italic(italicized)
      update_font_references(font)
    end

    # Changes font bold settings of cell
    def change_font_bold(bolded = false)
      validate_worksheet

      font = get_cell_font.dup
      font.set_bold(bolded)
      update_font_references(font)
    end

    # Changes font underline settings of cell
    def change_font_underline(underlined = false)
      validate_worksheet

      font = get_cell_font.dup
      font.set_underline(underlined)
      update_font_references(font)
    end

    def change_font_strikethrough(struckthrough = false)
      validate_worksheet

      font = get_cell_font.dup
      font.set_strikethrough(struckthrough)
      update_font_references(font)
    end

    # Helper method to update the font array and xf array
    def update_font_references(modified_font)
      xf = workbook.register_new_font(modified_font, get_cell_xf)
      self.style_index = workbook.register_new_xf(xf)
    end
    private :update_font_references

    # Performs correct modification based on what type of change_type is specified
    def font_switch(change_type, arg)
      case change_type
      when Worksheet::NAME          then change_font_name(arg)
      when Worksheet::SIZE          then change_font_size(arg)
      when Worksheet::COLOR         then change_font_color(arg)
      when Worksheet::ITALICS       then change_font_italics(arg)
      when Worksheet::BOLD          then change_font_bold(arg)
      when Worksheet::UNDERLINE     then change_font_underline(arg)
      when Worksheet::STRIKETHROUGH then change_font_strikethrough(arg)
      else raise 'Invalid change_type'
      end
    end

=begin
    def add_hyperlink(l)
      worksheet.hyperlinks ||= RubyXL::Hyperlinks.new
      worksheet.hyperlinks << RubyXL::Hyperlink.new(:ref => self.r, :location => l)
#    define_attribute(:'r:id',   :string)
#    define_attribute(:location, :string)
#    define_attribute(:tooltip,  :string)
#    define_attribute(:display,  :string)

    end

    def add_shared_string(str)
      self.datatype = RubyXL::DataType::SHARED_STRING
      self.raw_value = @workbook.shared_strings_container.add(str)
    end
=end

  end

end
