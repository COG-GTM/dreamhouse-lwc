import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';
import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';
import { percentBelowAsking, needsApproval } from './offerMath';

const OPEN_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge slds-badge_lightest',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-theme_info',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-theme_error'
};
const ACTIONS = {
    approve: { apex: approveOffer, verb: 'approved' },
    accept: { apex: acceptOffer, verb: 'accepted' },
    reject: { apex: rejectOffer, verb: 'rejected' }
};

export default class PropertyOffers extends LightningElement {
    buyerName = '';
    amount = null;
    context;
    error;
    isBusy = false;

    _recordId;
    _requestId = 0;
    _lastPropertyKey;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) {
            return;
        }
        this._recordId = value;
        this.buyerName = '';
        this.amount = null;
        this.context = undefined;
        this.error = undefined;
        this._lastPropertyKey = undefined;
        this.loadOffers();
    }

    // Reload when the asking price or status is edited elsewhere on the page.
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    wiredProperty({ data }) {
        if (!data) {
            return;
        }
        const key = `${data.fields.Price__c.value}|${data.fields.Status__c.value}`;
        const firstEmission = this._lastPropertyKey === undefined;
        this._lastPropertyKey = key;
        if (firstEmission && this.context && this.contextKey === key) {
            return;
        }
        this.loadOffers();
    }

    get contextKey() {
        return this.context
            ? `${this.context.askingPrice}|${this.context.propertyStatus}`
            : undefined;
    }

    async loadOffers() {
        if (!this._recordId) {
            return;
        }
        const requestId = ++this._requestId;
        const recordId = this._recordId;
        try {
            const context = await getOfferContext({ propertyId: recordId });
            if (requestId !== this._requestId) {
                return;
            }
            this.context = context;
            this.error = undefined;
        } catch (error) {
            if (requestId !== this._requestId) {
                return;
            }
            this.error = error;
        }
    }

    get offers() {
        const offers = this.context?.offers ?? [];
        const canApprove = this.context?.canApprove === true;
        const accepting = this.acceptingOffers;
        return offers.map((offer) => {
            const isOpen = accepting && OPEN_STATUSES.includes(offer.Status__c);
            return {
                ...offer,
                badgeClass: BADGE_CLASSES[offer.Status__c] ?? 'slds-badge',
                percentLabel: this.formatPercent(offer.Percent_Below_Asking__c),
                showApprove:
                    isOpen &&
                    canApprove &&
                    offer.Status__c === 'Needs Approval',
                showAccept:
                    isOpen &&
                    (offer.Status__c === 'Submitted' ||
                        offer.Status__c === 'Approved'),
                showReject: isOpen,
                approveTitle: `Approve offer from ${offer.Buyer_Name__c}`,
                acceptTitle: `Accept offer from ${offer.Buyer_Name__c}`,
                rejectTitle: `Reject offer from ${offer.Buyer_Name__c}`
            };
        });
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get acceptingOffers() {
        return this.context?.acceptingOffers === true;
    }

    get closedMessage() {
        return `This property is ${this.context?.propertyStatus} and is no longer taking offers.`;
    }

    get showClosedMessage() {
        return this.context && !this.acceptingOffers;
    }

    get previewPercent() {
        return percentBelowAsking(this.context?.askingPrice, this.amount);
    }

    get hasPreview() {
        return this.previewPercent !== null && Number(this.amount) > 0;
    }

    get previewNeedsApproval() {
        return needsApproval(this.previewPercent);
    }

    get previewText() {
        const label = this.formatPercent(this.previewPercent);
        return this.previewNeedsApproval
            ? `${label}, needs broker approval`
            : label;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error slds-text-body_small'
            : 'slds-text-color_weak slds-text-body_small';
    }

    get submitDisabled() {
        return (
            this.isBusy || !this.buyerName.trim() || !(Number(this.amount) > 0)
        );
    }

    get errorMessage() {
        return this.error ? reduceErrors(this.error).join(', ') : undefined;
    }

    formatPercent(value) {
        if (value === null || value === undefined) {
            return '';
        }
        const magnitude = Math.abs(value).toFixed(1);
        return value < 0
            ? `${magnitude}% above asking`
            : `${magnitude}% below asking`;
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value ?? '';
    }

    handleAmountChange(event) {
        const value = event.target.value;
        this.amount = value === '' || value === null ? null : Number(value);
    }

    async handleSubmit() {
        if (this.submitDisabled) {
            return;
        }
        this.isBusy = true;
        try {
            const offer = await submitOffer({
                propertyId: this._recordId,
                buyerName: this.buyerName,
                amount: this.amount
            });
            this.buyerName = '';
            this.amount = null;
            this.toast(
                'Offer submitted',
                `${offer.Buyer_Name__c}'s offer is ${offer.Status__c}.`,
                offer.Status__c === 'Needs Approval' ? 'warning' : 'success'
            );
            await this.loadOffers();
        } catch (error) {
            this.toast('Could not submit offer', reduceErrors(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleAction(event) {
        const { action, id } = event.currentTarget.dataset;
        const config = ACTIONS[action];
        if (!config) {
            return;
        }
        this.isBusy = true;
        try {
            const offer = await config.apex({ offerId: id });
            this.toast(
                `Offer ${config.verb}`,
                `${offer.Buyer_Name__c}'s offer was ${config.verb}.`,
                'success'
            );
            await this.loadOffers();
            if (action === 'accept') {
                await notifyRecordUpdateAvailable([
                    { recordId: this._recordId }
                ]);
            }
        } catch (error) {
            this.toast('Action failed', reduceErrors(error), 'error');
            await this.loadOffers();
        } finally {
            this.isBusy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: Array.isArray(message) ? message.join(', ') : message,
                variant
            })
        );
    }
}
