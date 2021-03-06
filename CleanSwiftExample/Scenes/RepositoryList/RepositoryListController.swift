import AsyncDisplayKit
import RxSwift
import RxCocoa

protocol RepositoryListDisplayLogic: class {
    
    var displayErrorRelay: PublishRelay<Error?> { get }
    var displayItemsRelay: PublishRelay<RepositoryListModels.RepositorySequence.ViewModel> { get }
    var displayPresentToRepositoryShow: PublishRelay<RepositoryListModels.RepositoryShow.ViewModel> { get }
}

class RepositoryListController:
ASViewController<RepositoryListContainerNode> & RepositoryListDisplayLogic {
    
    public var interactor: RepositoryListInteractorLogic?
    public var router: (RepositoryListRouterLogic & RepositoryListDataPassing)?
    
    public var displayErrorRelay: PublishRelay<Error?> = .init()
    public var displayItemsRelay: PublishRelay<RepositoryListModels.RepositorySequence.ViewModel> = .init()
    public var displayPresentToRepositoryShow: PublishRelay<RepositoryListModels.RepositoryShow.ViewModel> = .init()
    
    private var batchContext: ASBatchContext?
    private var items: [RepositoryListModels.RepositorySequence.ViewModel.CellViewModel] = []
    private var since: Int? {
        return self.items.last?.identifier
    }
    
    let disposeBag = DisposeBag()
    
    init() {
        super.init(node: .init())
        self.node.tableNode.delegate = self
        self.node.tableNode.dataSource = self
        self.configureVIPCycle()
        self.configureDisplay()
    }
    
    func configureVIPCycle() {
        let viewController = self
        let presenter = RepositoryListPresenter()
        let interactor = RepositoryListInteractor()
        let router = RepositoryListRouter.init()
        
        presenter
            .bind(to: viewController)
            .disposed(by: disposeBag)
        
        interactor
            .bind(to: presenter)
            .disposed(by: disposeBag)
        
        router
            .bind(to: viewController)
            .disposed(by: disposeBag)
        
        router.dataStore = interactor
        viewController.router = router
        viewController.interactor = interactor
    }
    
    func configureDisplay() {
        
        self.displayItemsRelay
            .subscribe(onNext: { [weak self] viewModel in
                guard let self = self else { return }
                
                let startIndex = self.items.count
                self.items.append(contentsOf: viewModel.repoCellViewModels)
                let indexPaths: [IndexPath] = (startIndex..<startIndex + viewModel.repoCellViewModels.count)
                    .map({ index in
                        return IndexPath.init(row: index, section: 0)
                    })
                
                self.node.tableNode.performBatchUpdates({
                    self.node.tableNode.insertRows(at: indexPaths, with: .fade)
                }, completion: { fin in
                    self.batchContext?.completeBatchFetching(fin)
                })
            })
            .disposed(by: disposeBag)
        
        self.displayErrorRelay
            .subscribe(onNext: { [weak self] error in
                self?.batchContext?.completeBatchFetching(true)
            })
            .disposed(by: disposeBag)
        
        self.displayPresentToRepositoryShow
            .subscribe(onNext: { [weak self] _ in
                self?.router?.presentToRepositoryShowRelay.accept(())
            })
            .disposed(by: disposeBag)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RepositoryListController: ASTableDataSource {
    
    func numberOfSections(in tableNode: ASTableNode) -> Int {
        return 1
    }
    
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return self.items.count
    }
    
    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        return {
            guard self.items.count > indexPath.row else { return ASCellNode() }
            let cellNode = RepositoryListCellNode()
            let viewModel = self.items[indexPath.row]
            
            cellNode.bind(viewModel: viewModel)
            
            if let interactor = self.interactor {
                
                cellNode.profileNode.rx.tap
                    .withValue(type: Int.self, value: viewModel.identifier)
                    .map({ RepositoryListModels.RepositoryShow.Request.init(repoID: $0) })
                    .bind(to: interactor.didTapRepositoryCell)
                    .disposed(by: cellNode.disposeBag)
            }
            
            return cellNode
        }
    }
}

extension RepositoryListController: ASTableDelegate {
    
    func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
        return self.batchContext == nil || !(self.batchContext?.isFetching() ?? true)
    }
    
    func tableNode(_ tableNode: ASTableNode,
                   willBeginBatchFetchWith context: ASBatchContext) {
        self.interactor?.loadMoreRelay.accept(RepositoryListModels.RepositorySequence.Request(since: self.since))
        self.batchContext = context
    }
}
