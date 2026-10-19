import { createElement } from '@lwc/engine-dom';
import PropertyOffers, { percentBelowAsking } from 'c/propertyOffers';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

jest.mock(
    '@salesforce/apex/OfferController.getOfferContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.submitOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.approveOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.acceptOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.rejectOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const PROPERTY_ID = 'a0Vaj00000ec4VAEAY';
const JANE = {
    Id: 'a1Aaj0000000001AAA',
    Buyer_Name__c: 'Jane Buyer',
    Amount__c: 820000,
    Percent_Below_Asking__c: 3.0,
    Status__c: 'Submitted'
};
const SAM = {
    Id: 'a1Aaj0000000002AAA',
    Buyer_Name__c: 'Sam Lowball',
    Amount__c: 720000,
    Percent_Below_Asking__c: 14.8,
    Status__c: 'Needs Approval'
};

function context(overrides = {}) {
    return {
        askingPrice: 845000,
        propertyStatus: 'Available',
        propertyOpen: true,
        canApprove: false,
        approvalThreshold: 10,
        offers: [],
        ...overrides
    };
}

function propertyRecord(price, status) {
    return {
        fields: {
            Price__c: { value: price },
            Status__c: { value: status }
        }
    };
}

async function flushPromises() {
    for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

async function createComponent(ctx = context()) {
    getOfferContext.mockResolvedValue(ctx);
    const element = createElement('c-property-offers', {
        is: PropertyOffers
    });
    element.recordId = PROPERTY_ID;
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function card(element) {
    return element.shadowRoot.querySelector('lightning-card');
}

function input(element, label) {
    return Array.from(
        element.shadowRoot.querySelectorAll('lightning-input')
    ).find((el) => el.label === label);
}

function buttonsFor(element, offerId) {
    const item = element.shadowRoot.querySelector(`li[data-id="${offerId}"]`);
    return Array.from(item.querySelectorAll('lightning-button')).map(
        (button) => button.label
    );
}

function offerButton(element, offerId, label) {
    const item = element.shadowRoot.querySelector(`li[data-id="${offerId}"]`);
    return Array.from(item.querySelectorAll('lightning-button')).find(
        (el) => el.label === label
    );
}

async function typeOffer(element, buyer, amount) {
    const buyerInput = input(element, 'Buyer name');
    buyerInput.value = buyer;
    buyerInput.dispatchEvent(new CustomEvent('change'));
    const amountInput = input(element, 'Offer amount');
    amountInput.value = amount;
    amountInput.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

function submitButton(element) {
    return Array.from(
        element.shadowRoot.querySelectorAll('lightning-button')
    ).find((el) => el.label === 'Submit offer');
}

function preview(element) {
    return element.shadowRoot.querySelector('[data-id="preview"]');
}

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe('percentBelowAsking', () => {
        it('rounds half-up to one decimal like Apex', () => {
            expect(percentBelowAsking(845000, 720000)).toBe(14.8);
            expect(percentBelowAsking(845000, 820000)).toBe(3);
            expect(percentBelowAsking(100000, 89950)).toBe(10.1);
            expect(percentBelowAsking(100000, 89951)).toBe(10);
            expect(percentBelowAsking(100000, 110000)).toBe(-10);
            expect(percentBelowAsking(100000, 100000)).toBe(0);
            expect(percentBelowAsking(0, 100)).toBeNull();
        });
    });

    it('loads offers for the record and shows an empty card', async () => {
        const element = await createComponent();

        expect(getOfferContext).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID
        });
        expect(card(element).title).toBe('Offers (0)');
        expect(
            element.shadowRoot.querySelector('.empty').textContent
        ).toContain('No offers yet');
        expect(submitButton(element).disabled).toBe(true);
    });

    it('shows status badges and only the allowed actions', async () => {
        const element = await createComponent(context({ offers: [SAM, JANE] }));

        expect(card(element).title).toBe('Offers (2)');
        const badges = Array.from(
            element.shadowRoot.querySelectorAll('lightning-badge')
        ).map((badge) => badge.label);
        expect(badges).toEqual(['Needs Approval', 'Submitted']);
        expect(buttonsFor(element, SAM.Id)).toEqual(['Reject']);
        expect(buttonsFor(element, JANE.Id)).toEqual(['Accept', 'Reject']);
    });

    it('shows Approve to brokers and Accept once approved', async () => {
        const approved = { ...SAM, Status__c: 'Approved' };
        const element = await createComponent(
            context({ canApprove: true, offers: [SAM] })
        );
        expect(buttonsFor(element, SAM.Id)).toEqual(['Approve', 'Reject']);

        getOfferContext.mockResolvedValue(
            context({ canApprove: true, offers: [approved] })
        );
        approveOffer.mockResolvedValue();
        offerButton(element, SAM.Id, 'Approve').click();
        await flushPromises();

        expect(approveOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(buttonsFor(element, SAM.Id)).toEqual(['Accept', 'Reject']);
    });

    it('previews the discount and warns when approval is needed', async () => {
        const element = await createComponent();

        await typeOffer(element, 'Sam Lowball', '720000');
        expect(preview(element).textContent).toContain(
            '14.8% below asking, needs broker approval'
        );

        await typeOffer(element, 'Jane Buyer', '820000');
        expect(preview(element).textContent.trim()).toBe('3.0% below asking');

        await typeOffer(element, 'Jane Buyer', '900000');
        expect(preview(element).textContent.trim()).toBe('6.5% above asking');
    });

    it('treats the 10% boundary the same way as Apex', async () => {
        const element = await createComponent(context({ askingPrice: 100000 }));

        await typeOffer(element, 'Edge', '89951');
        expect(preview(element).textContent.trim()).toBe('10.0% below asking');

        await typeOffer(element, 'Edge', '89950');
        expect(preview(element).textContent).toContain(
            '10.1% below asking, needs broker approval'
        );
    });

    it('submits an offer, toasts and reloads', async () => {
        const element = await createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        submitOffer.mockResolvedValue({ ...SAM });

        await typeOffer(element, 'Sam Lowball', '720000');
        getOfferContext.mockResolvedValue(context({ offers: [SAM] }));
        submitButton(element).click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Sam Lowball',
            amount: 720000
        });
        expect(toastHandler).toHaveBeenCalledTimes(1);
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('warning');
        expect(getOfferContext).toHaveBeenCalledTimes(2);
        expect(card(element).title).toBe('Offers (1)');
        expect(input(element, 'Buyer name').value).toBe('');
    });

    it('shows a toast when submit fails', async () => {
        const element = await createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        submitOffer.mockRejectedValue({
            body: { message: 'This property is Closed.' }
        });

        await typeOffer(element, 'Jane', '820000');
        submitButton(element).click();
        await flushPromises();

        const toast = toastHandler.mock.calls[0][0].detail;
        expect(toast.variant).toBe('error');
        expect(toast.message).toBe('This property is Closed.');
    });

    it('accepting an offer refreshes the property record', async () => {
        const element = await createComponent(context({ offers: [JANE] }));
        acceptOffer.mockResolvedValue();
        getOfferContext.mockResolvedValue(
            context({
                propertyOpen: false,
                propertyStatus: 'Under Agreement',
                offers: [{ ...JANE, Status__c: 'Accepted' }]
            })
        );

        offerButton(element, JANE.Id, 'Accept').click();
        await flushPromises();

        expect(acceptOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);
        expect(buttonsFor(element, JANE.Id)).toEqual([]);
        expect(input(element, 'Buyer name')).toBeUndefined();
        expect(
            element.shadowRoot.querySelector('[data-id="closed"]').textContent
        ).toContain('Under Agreement');
    });

    it('rejects an offer and reports action errors', async () => {
        const element = await createComponent(context({ offers: [JANE] }));
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        rejectOffer.mockRejectedValue({
            body: { message: 'Only open offers can be rejected.' }
        });

        offerButton(element, JANE.Id, 'Reject').click();
        await flushPromises();

        expect(rejectOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Only open offers can be rejected.'
        );
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('reloads when recordId changes and ignores stale responses', async () => {
        let resolveFirst;
        getOfferContext.mockReturnValueOnce(
            new Promise((resolve) => {
                resolveFirst = resolve;
            })
        );
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);

        getOfferContext.mockResolvedValueOnce(context({ offers: [SAM] }));
        element.recordId = 'a0Vaj00000ec4VBEAY';
        await flushPromises();
        resolveFirst(context({ offers: [JANE, SAM] }));
        await flushPromises();

        expect(getOfferContext).toHaveBeenLastCalledWith({
            propertyId: 'a0Vaj00000ec4VBEAY'
        });
        expect(card(element).title).toBe('Offers (1)');
    });

    it('clears the offer form when the record changes', async () => {
        const element = await createComponent();
        await typeOffer(element, 'Sam Lowball', '720000');

        element.recordId = 'a0Vaj00000ec4VBEAY';
        await flushPromises();

        expect(input(element, 'Buyer name').value).toBe('');
        expect(input(element, 'Offer amount').value).toBeUndefined();
        expect(preview(element)).toBeNull();
    });

    it('reloads offers when the asking price or status changes', async () => {
        const element = await createComponent();
        getRecord.emit(propertyRecord(845000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(1);

        getRecord.emit(propertyRecord(845000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(1);

        getOfferContext.mockResolvedValue(context({ askingPrice: 1000000 }));
        getRecord.emit(propertyRecord(1000000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(2);

        await typeOffer(element, 'Jane Buyer', '820000');
        expect(preview(element).textContent).toContain(
            '18.0% below asking, needs broker approval'
        );
    });

    it('reloads when the first property update differs from loaded offers', async () => {
        await createComponent();
        getOfferContext.mockResolvedValue(context({ askingPrice: 1000000 }));
        getRecord.emit(propertyRecord(1000000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(2);
    });

    it('refetches once when offers load with an outdated price', async () => {
        let resolveFirst;
        getOfferContext.mockReturnValueOnce(
            new Promise((resolve) => {
                resolveFirst = resolve;
            })
        );
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        getRecord.emit(propertyRecord(1000000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(1);

        getOfferContext.mockResolvedValue(context({ askingPrice: 1000000 }));
        resolveFirst(context());
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(2);

        await typeOffer(element, 'Jane Buyer', '820000');
        expect(preview(element).textContent).toContain('18.0% below asking');
    });

    it('shows an error panel when loading fails', async () => {
        getOfferContext.mockRejectedValue({ body: { message: 'No access' } });
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-error-panel')
        ).not.toBeNull();
    });

    it('is accessible', async () => {
        const element = await createComponent(
            context({ canApprove: true, offers: [SAM, JANE] })
        );
        await expect(element).toBeAccessible();
    });
});
