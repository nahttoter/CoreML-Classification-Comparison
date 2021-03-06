//
//  FlickrPhotoViewController.swift
//  MLKit-Vision-Demo
//
//  Created by Matthias Wagner on 10.06.18.
//  Copyright © 2018 Matthias Wagner. All rights reserved.
//

import UIKit
import ReactiveSwift
import ReactiveCocoa

protocol ImageCollectionViewModel {
    var photos: Property<[Photo]> { get }
    var queryStatus: Property<QueryStatus> { get }
    var lastQuery: String? { get }

    var navigationTitle: String { get }

    func onNextPage()
    func onLastPage()
    func searchFor(_ query: String, page: Int?)
}

class ImagesViewController: UIViewController {

    // MARK: - IBOutlets

    @IBOutlet private weak var collectionView: UICollectionView!
    @IBOutlet private weak var flowLayout: UICollectionViewFlowLayout!

    @IBOutlet private weak var nextPageButtonBelow: UIButton!
    @IBOutlet private weak var lastPageButtonBelow: UIButton!

    @IBOutlet private weak var pageControlView: UIView!
    @IBOutlet private weak var pageCountLabel: UILabel!
    @IBOutlet private weak var pageControlHeightConstraint: NSLayoutConstraint!

    @IBOutlet private weak var emptyViewLabel: UILabel!
    
    // MARK: - NavigationBar Buttons

    var nextPageButton: UIBarButtonItem!
    var lastPageButton: UIBarButtonItem!

    // MARK: - Properties

    private var disposableBag = CompositeDisposable()

    private let searchController = UISearchController(searchResultsController: nil)
    private let isSearchBarActive = MutableProperty<Bool>(false)

    private let cellIdentifier = "ImageCollectionCell"

    var viewModel: ImageCollectionViewModel!

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupEmptyViewLabel()
        setupSearch()
        setupCollectionView()
        bindViewModel()
        setupNavigationBarButtons()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        disposableBag.dispose()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bindKeyboard()
    }

    // MARK: - Search Setup

    private func setupEmptyViewLabel() {
        emptyViewLabel.text = Strings.ImagesViewController.emptyViewDescription
        emptyViewLabel.reactive.isHidden <~ viewModel.photos.producer.map { $0.count > 0 }
    }

    private func setupCollectionView() {
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: cellIdentifier, bundle: nil), forCellWithReuseIdentifier: cellIdentifier)

        flowLayout.itemSize = CGSize(width: collectionView.bounds.width / 3 - 1, height: collectionView.bounds.width / 3 - 1)
        flowLayout.minimumLineSpacing = 1
    }

    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Images"
        searchController.searchBar.returnKeyType = .done
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        definesPresentationContext = true

        // Cancel text
        searchController.searchBar.tintColor = UIColor.white

        // Background
        if let textfield = searchController.searchBar.value(forKey: "searchField") as? UITextField {
            if let backgroundview = textfield.subviews.first {
                backgroundview.backgroundColor = UIColor.white
                backgroundview.layer.cornerRadius = 10
                backgroundview.clipsToBounds = true
            }
        }
    }

    private func setupNavigationBarButtons() {
        nextPageButton = UIBarButtonItem(title: "Next Page", style: .plain, target: self, action: #selector(onNextPage(_:)))
        lastPageButton = UIBarButtonItem(title: "Last Page", style: .plain, target: self, action: #selector(onLastPage(_:)))

        pageControlView.backgroundColor = Colors.Main.red
        nextPageButtonBelow.backgroundColor = .clear
        lastPageButtonBelow.backgroundColor = .clear
        pageCountLabel.textColor = .white
        lastPageButtonBelow.tintColor = .white
        nextPageButtonBelow.tintColor = .white

        SignalProducer
            .combineLatest(viewModel.queryStatus.producer,
                           isSearchBarActive.producer)
            .startWithValues { [weak self] queryStatus, isSearchBarActive in
                guard let `self` = self else { return }

                var hasNextPage = false
                var hasLastPage = false

                if let page = queryStatus.currentPage,
                    let pageCount = queryStatus.pageCount,
                    queryStatus.lastQuery != nil {

                    hasNextPage = page + 1 <= pageCount ? true : false
                    hasLastPage = page - 1 > 0 ? true : false
                }

                self.navigationItem.rightBarButtonItem = hasNextPage ? self.nextPageButton : nil
                self.navigationItem.leftBarButtonItem = hasLastPage ? self.lastPageButton : nil

                if isSearchBarActive {
                    self.pageControlView.isHidden = false
                    self.pageControlHeightConstraint.constant = 45
                }

                self.nextPageButtonBelow.isHidden = hasNextPage ? false : true
                self.lastPageButtonBelow.isHidden = hasLastPage ? false : true

                self.navigationItem.title = queryStatus.currentPage != nil
                    ? "Page: \(queryStatus.currentPage!)/\(queryStatus.pageCount!)"
                    : self.viewModel.navigationTitle

                self.pageCountLabel.text = queryStatus.currentPage != nil
                    ? "Page: \(queryStatus.currentPage!)/\(queryStatus.pageCount!)"
                    : "Enter a search tag"
            }

    }

    // MARK: - Keyboard

    private func bindKeyboard() {
        disposableBag = CompositeDisposable()
        disposableBag += KeyboardObserver.shared.keyboardWillShowSignal.producer
            .skipNil()
            .startWithValues { keyboardNotification in
                self.collectionView.contentInset.bottom = keyboardNotification.keyboardEndFrame.height
            }

        disposableBag += KeyboardObserver.shared.keyboardWillHideSignal.producer
            .skipNil()
            .startWithValues { [weak self] keyboardNotification in
                self?.collectionView.contentInset.bottom = 0
        }
    }

    // MARK: - Datasource

    private func bindViewModel() {
        viewModel.photos.producer.startWithValues { [weak self] photos in
            guard let `self` = self else { return }

            self.collectionView.reloadData()
        }
    }

    // MARK: - IBActions

    @IBAction func onNextPage(_ sender: Any) {
        viewModel.onNextPage()
    }

    @IBAction func onLastPage(_ sender: Any) {
        viewModel.onLastPage()
    }
}

// MARK: - UICollectionViewDataSource

extension ImagesViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if let photos = viewModel?.photos.value {
            return photos.count
        }
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as! ImageCollectionCell

        if let viewModel = viewModel {
            cell.configure(photo: viewModel.photos.value[indexPath.row])
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension ImagesViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath) as! ImageCollectionCell

        let photo = cell.photo
        let imageProcessingViewModel = ImageProcessingViewModel(photo: photo!)
        let imageProcessingViewController: ImageProcessingViewController = UIStoryboard(.processing).instantiateViewController()

        imageProcessingViewController.viewModel = imageProcessingViewModel

        navigationItem.searchController?.searchBar.resignFirstResponder()
        navigationController?.pushViewController(imageProcessingViewController, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension ImagesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let strippedString = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces) else { return }

        if strippedString.count < 3 || strippedString == viewModel.lastQuery { return }

        viewModel.searchFor(strippedString.lowercased(), page: nil)
    }
}

// MARK: - UISearchBarDelegate

extension ImagesViewController: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        isSearchBarActive.value = true
        return true
    }

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        isSearchBarActive.value = false
        return true
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchController.searchBar.text = viewModel.lastQuery
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        pageControlView.isHidden = true
        pageControlHeightConstraint.constant = 0
    }
}
