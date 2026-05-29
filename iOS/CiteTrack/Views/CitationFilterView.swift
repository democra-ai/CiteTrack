import SwiftUI

// MARK: - Citation Filter View
struct CitationFilterView: View {
    @Binding var filter: CitationFilter
    @Environment(\.dismiss) private var dismiss
    
    @State private var sortBy: CitationFilter.SortOption
    @State private var searchKeyword: String
    @State private var authorFilter: String
    @State private var startYear: Int
    @State private var endYear: Int
    @State private var useYearRange: Bool
    
    init(filter: Binding<CitationFilter>) {
        self._filter = filter
        self._sortBy = State(initialValue: filter.wrappedValue.sortBy)
        self._searchKeyword = State(initialValue: filter.wrappedValue.searchKeyword ?? "")
        self._authorFilter = State(initialValue: filter.wrappedValue.authorFilter ?? "")
        
        let currentYear = Calendar.current.component(.year, from: Date())
        if let range = filter.wrappedValue.yearRange {
            self._startYear = State(initialValue: range.start)
            self._endYear = State(initialValue: range.end)
            self._useYearRange = State(initialValue: true)
        } else {
            self._startYear = State(initialValue: currentYear - 5)
            self._endYear = State(initialValue: currentYear)
            self._useYearRange = State(initialValue: false)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // 排序选项
                Section("sort_by".localized) {
                    Picker("sort_option".localized, selection: $sortBy) {
                        ForEach(CitationFilter.SortOption.allCases, id: \.self) { option in
                            Text(option.displayName)
                        }
                    }
                }
                
                // 年份范围
                Section("year_range".localized) {
                    Toggle("use_year_filter".localized, isOn: $useYearRange)
                    
                    if useYearRange {
                        Stepper("start_year".localized + ": \(startYear)", value: $startYear, in: 1900...2100)
                        Stepper("end_year".localized + ": \(endYear)", value: $endYear, in: 1900...2100)
                    }
                }
                
                // 关键词搜索
                Section("search".localized) {
                    TextField("search_keyword".localized, text: $searchKeyword)
                        .autocapitalization(.none)
                }
                
                // 作者筛选
                Section("author_filter".localized) {
                    TextField("author_name".localized, text: $authorFilter)
                        .autocapitalization(.words)
                }
                
                // 清除按钮
                Section {
                    Button(action: clearFilters) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("clear_filters".localized)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .liquidGlassCanvas()
            .navigationTitle("filter_options".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localized) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("apply".localized) {
                        applyFilters()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func applyFilters() {
        filter.sortBy = sortBy
        filter.searchKeyword = searchKeyword.isEmpty ? nil : searchKeyword
        filter.authorFilter = authorFilter.isEmpty ? nil : authorFilter
        
        if useYearRange {
            filter.yearRange = CitationFilter.YearRange(start: startYear, end: endYear)
        } else {
            filter.yearRange = nil
        }
    }
    
    private func clearFilters() {
        sortBy = .yearDescending
        searchKeyword = ""
        authorFilter = ""
        useYearRange = false
        
        let currentYear = Calendar.current.component(.year, from: Date())
        startYear = currentYear - 5
        endYear = currentYear
    }
}

// MARK: - Preview
struct CitationFilterView_Previews: PreviewProvider {
    static var previews: some View {
        CitationFilterView(filter: .constant(CitationFilter()))
    }
}
